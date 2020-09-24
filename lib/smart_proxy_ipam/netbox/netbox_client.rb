require 'yaml'
require 'json'
require 'net/http'
require 'monitor'
require 'concurrent'
require 'time'
require 'uri'
require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_helper'
require 'smart_proxy_ipam/api_resource'
require 'smart_proxy_ipam/ip_cache'

module Proxy::Netbox
  # Implementation class for External IPAM provider Netbox
  class NetboxClient
    include Proxy::Log
    include Proxy::Ipam::IpamHelper

    @ip_cache = nil
    MAX_RETRIES = 5

    def initialize(conf)
      @api_base = "#{conf[:url]}/api/"
      @token = conf[:token]
      @api_resource = Proxy::Ipam::ApiResource.new(api_base: @api_base, token: 'Token ' + @token)
      @ip_cache = Proxy::Ipam::IpCache.new(provider: 'netbox')
    end

    def get_ipam_subnet(cidr, group_id = nil)
      if group_id.nil?
        get_ipam_subnet_by_cidr(cidr)
      else
        get_ipam_subnet_by_group(cidr, group_id)
      end
    end

    def get_ipam_subnet_by_group(cidr, group_id)
      response = @api_resource.get("ipam/prefixes/?status=active&prefix=#{cidr}&vrf_id=#{group_id}")
      json_body = JSON.parse(response.body)
      return nil if json_body['count'].zero?
      subnet = subnet_from_result(json_body['results'][0])
      return subnet if json_body['results']
    end

    def get_ipam_subnet_by_cidr(cidr)
      response = @api_resource.get("ipam/prefixes/?status=active&prefix=#{cidr}")
      json_body = JSON.parse(response.body)
      return nil if json_body['count'].zero?
      subnet = subnet_from_result(json_body['results'][0])
      return subnet if json_body['results']
    end

    def get_ipam_groups
      response = @api_resource.get('ipam/vrfs/')
      json_body = JSON.parse(response.body)
      groups = []

      return nil if json_body['count'].zero?

      json_body['results'].each do |group|
        groups.push({
          name: group['name'],
          description: group['description']
        })
      end

      groups
    end

    def get_ipam_group(group_name)
      response = @api_resource.get("ipam/vrfs/?name=#{group_name}")
      json_body = JSON.parse(response.body)
      return nil if json_body['count'].zero?

      group = {
        id: json_body['results'][0]['id'],
        name: json_body['results'][0]['name'],
        description: json_body['results'][0]['description']
      }

      return group if json_body['results']
    end

    def get_group_id(group_name)
      return nil if group_name.nil? || group_name.empty?
      group = get_ipam_group(group_name)
      raise errors[:no_group] if group.nil?
      group[:id]
    end

    def get_ipam_subnets(group_name)
      if group_name.nil?
        response = @api_resource.get('ipam/prefixes/?status=active')
      else
        group_id = get_group_id(group_name)
        response = @api_resource.get("ipam/prefixes/?status=active&vrf_id=#{group_id}")
      end

      json_body = JSON.parse(response.body)
      return nil if json_body['count'].zero?
      subnets = []

      json_body['results'].each do |subnet|
        subnets.push({
          subnet: subnet['prefix'].split('/').first,
          mask: subnet['prefix'].split('/').last,
          description: subnet['description'],
          id: subnet['id']
        })
      end

      return subnets if json_body['results']
    end

    def ip_exists?(ip, subnet_id, group_name)
      group_id = get_group_id(group_name)
      url = "ipam/ip-addresses/?address=#{ip}"
      url += "&prefix_id=#{subnet_id}" unless subnet_id.nil?
      url += "&vrf_id=#{group_id}" unless group_id.nil?
      response = @api_resource.get(url)
      json_body = JSON.parse(response.body)
      return false if json_body['count'].zero?
      true
    end

    def add_ip_to_subnet(ip, params)
      desc = 'Address auto added by Foreman'
      address = "#{ip}/#{params[:cidr].split('/').last}"
      group_name = params[:group_name]

      if group_name.nil? || group_name.empty?
        data = { address: address, nat_outside: 0, description: desc }
      else
        group_id = get_group_id(group_name)
        data = { vrf: group_id, address: address, nat_outside: 0, description: desc }
      end

      response = @api_resource.post('ipam/ip-addresses/', data.to_json)
      return nil if response.code == '201'
      { error: "Unable to add #{address} in External IPAM server" }
    end

    def delete_ip_from_subnet(ip, params)
      group_name = params[:group_name]

      if group_name.nil? || group_name.empty?
        response = @api_resource.get("ipam/ip-addresses/?address=#{ip}")
      else
        group_id = get_group_id(group_name)
        response = @api_resource.get("ipam/ip-addresses/?address=#{ip}&vrf_id=#{group_id}")
      end

      json_body = JSON.parse(response.body)

      return { error: errors[:no_ip] } if json_body['count'].zero?

      address_id = json_body['results'][0]['id']
      response = @api_resource.delete("ipam/ip-addresses/#{address_id}/")
      return nil if response.code == '204'
      { error: "Unable to delete #{ip} in External IPAM server" }
    end

    def get_next_ip(mac, cidr, group_name)
      subnet = get_ipam_subnet(cidr, group_name)
      raise errors[:no_subnet] if subnet.nil?
      response = @api_resource.get("ipam/prefixes/#{subnet[:id]}/available-ips/?limit=1")
      json_body = JSON.parse(response.body)
      group = group_name.nil? ? '' : group_name
      @ip_cache.set_group(group, {}) if @ip_cache.get_group(group).nil?
      subnet_hash = @ip_cache.get_cidr(group, cidr)
      next_ip = nil

      return nil if json_body.empty?

      if subnet_hash&.key?(mac.to_sym)
        next_ip = @ip_cache.get_ip(group, cidr, mac)
      else
        new_ip = json_body[0]['address'].split('/').first
        ip_not_in_cache = subnet_hash.nil? ? true : !subnet_hash.to_s.include?(new_ip.to_s)

        if ip_not_in_cache
          next_ip = new_ip.to_s
          @ip_cache.add(new_ip, mac, cidr, group)
        else
          next_ip = find_new_ip(subnet[:id], new_ip, mac, cidr, group)
        end

        return { error: "Unable to find another available IP address in subnet #{cidr}" } if next_ip.nil?
        return { error: "It is possible that there are no more free addresses in subnet #{cidr}. Available IP's may be cached, and could become available after in-memory IP cache is cleared(up to #{@ip_cache.get_cleanup_interval} seconds)." } unless usable_ip(next_ip, cidr)
      end

      next_ip
    end

    def groups_supported?
      true
    end

    def authenticated?
      !@token.nil?
    end

    private

    def subnet_from_result(result)
      {
        subnet: result['prefix'].split('/').first,
        mask: result['prefix'].split('/').last,
        description: result['description'],
        id: result['id']
      }
    end

    # Called when next available IP from external IPAM has been cached by another user/host, but
    # not actually persisted in external IPAM. Will increment the IP(MAX_RETRIES times), and
    # see if it is available in external IPAM.
    def find_new_ip(subnet_id, ip, mac, cidr, group_name)
      found_ip = nil
      temp_ip = ip
      retry_count = 0

      loop do
        new_ip = increment_ip(temp_ip)
        ipam_ip = ip_exists?(new_ip, subnet_id, group_name)

        # If new IP doesn't exist in IPAM and not in the cache
        if !ipam_ip && !@ip_cache.ip_exists(new_ip, cidr, group_name)
          found_ip = new_ip.to_s
          @ip_cache.add(found_ip, mac, cidr, group_name)
          break
        end

        temp_ip = new_ip
        retry_count += 1
        break if retry_count >= MAX_RETRIES
      end

      # Return the original IP found in external ipam if no new ones found after MAX_RETRIES
      return ip if found_ip.nil?

      found_ip
    end
  end
end
