require 'yaml'
require 'json'
require 'net/http'
require 'monitor'
require 'concurrent'
require 'time'
require 'uri'
require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/ipam_helper'
require 'smart_proxy_ipam/api_resource'
require 'smart_proxy_ipam/ip_cache'

module Proxy::Ipam
  # Implementation class for External IPAM provider phpIPAM
  class PhpipamClient
    include Proxy::Log
    include IpamHelper

    @ip_cache = nil
    MAX_RETRIES = 5

    def initialize
      provider = :phpipam
      config = Proxy::Ipam.get_config[provider]
      raise 'The configuration for phpipam is not present in externalipam.yml' unless config
      api_base = "#{config[:url]}/api/#{config[:user]}/"
      @api_resource = ApiResource.new(api_base: api_base, config: config)
      @api_resource.authenticate('/user/') 
      @ip_cache = IpCache.new(provider: provider)
    end

    def get_subnet(cidr, group_id = nil)
      if group_id.nil? || group_id.empty?
        get_subnet_by_cidr(cidr)
      else
        get_subnet_by_group(cidr, group_id)
      end
    end

    def get_subnet_by_group(cidr, group_id, include_id = true)
      subnets = get_subnets(group_id, include_id)
      subnet_id = nil

      subnets[:data].each do |subnet|
        subnet_cidr = subnet[:subnet] + '/' + subnet[:mask]
        subnet_id = subnet[:id] if subnet_cidr == cidr
      end

      return { message: 'No subnet found' } if subnet_id.nil?

      response = @api_resource.get("subnets/#{subnet_id}/")
      json_body = JSON.parse(response.body)

      data = {
        id: json_body['data']['id'],
        subnet: json_body['data']['subnet'],
        mask: json_body['data']['mask'],
        description: json_body['data']['description']
      }

      return { data: data } if json_body['data']
    end

    def get_subnet_by_cidr(cidr)
      response = @api_resource.get("subnets/cidr/#{cidr}")
      json_body = JSON.parse(response.body)

      return { message: 'No subnet found' } if json_body['data'].nil?

      data = {
        id: json_body['data'][0]['id'],
        subnet: json_body['data'][0]['subnet'],
        mask: json_body['data'][0]['mask'],
        description: json_body['data'][0]['description']
      }

      return { data: data } if json_body['data']
    end

    def get_group(group_name)
      response = @api_resource.get("sections/#{group_name}/")
      json_body = JSON.parse(response.body)
      return { message: json_body['message'] } if json_body['message']

      data = {
        id: json_body['data']['id'],
        name: json_body['data']['name'],
        description: json_body['data']['description']
      }

      return { data: data } if json_body['data']
    end

    def get_groups
      response = @api_resource.get('sections/')
      json_body = JSON.parse(response.body)
      return { message: json_body['message'] } if json_body['message']

      data = []
      json_body['data'].each do |group|
        data.push({
          id: group['id'],
          name: group['name'],
          description: group['description']
        })
      end

      return { data: data } if json_body['data']
    end

    def get_subnets(group_id, include_id = true)
      response = @api_resource.get("sections/#{group_id}/subnets/")
      json_body = JSON.parse(response.body)
      return { message: json_body['message'] } if json_body['message']

      data = []
      json_body['data'].each do |group|
        item = {
          subnet: group['subnet'],
          mask: group['mask'],
          description: group['description']
        }
        item[:id] = group['id'] if include_id
        data.push(item)
      end

      return { data: data } if json_body['data']
    end

    def ip_exists?(ip, subnet_id)
      response = @api_resource.get("subnets/#{subnet_id}/addresses/#{ip}/")
      json_body = JSON.parse(response.body)
      json_body['success']
    end

    def add_ip_to_subnet(ip, subnet_id, desc)
      data = { subnetId: subnet_id, ip: ip, description: desc }
      response = @api_resource.post('addresses/', data)
      json_body = JSON.parse(response.body)
      return nil if json_body['code'] == 201
      { error: 'Unable to add IP to External IPAM' }
    end

    def delete_ip_from_subnet(ip, subnet_id)
      response = @api_resource.delete("addresses/#{ip}/#{subnet_id}/")
      json_body = JSON.parse(response.body)
      return nil if json_body['success']
      { error: 'Unable to delete IP from External IPAM' }
    end

    def get_next_ip(subnet_id, mac, cidr, group_name)
      response = @api_resource.get("subnets/#{subnet_id}/first_free/")
      json_body = JSON.parse(response.body)
      group = group_name.nil? ? '' : group_name
      @ip_cache.set_group(group, {}) if @ip_cache.get_group(group).nil?
      subnet_hash = @ip_cache.get_cidr(group, cidr)

      return { message: json_body['message'] } if json_body['message']

      if subnet_hash&.key?(mac.to_sym)
        json_body['data'] = @ip_cache.get_ip(group, cidr, mac)
      else
        next_ip = nil
        new_ip = json_body['data']
        ip_not_in_cache = subnet_hash.nil? ? true : !subnet_hash.to_s.include?(new_ip.to_s)

        if ip_not_in_cache
          next_ip = new_ip.to_s
          @ip_cache.add(new_ip, mac, cidr, group)
        else
          next_ip = find_new_ip(subnet_id, new_ip, mac, cidr, group)
        end

        return { error: "Unable to find another available IP address in subnet #{cidr}" } if next_ip.nil?
        return { error: "It is possible that there are no more free addresses in subnet #{cidr}. Available IP's may be cached, and could become available after in-memory IP cache is cleared(up to #{@ip_cache.get_cleanup_interval} seconds)." } unless usable_ip(next_ip, cidr)

        json_body['data'] = next_ip
      end

      { data: json_body['data'] }
    end

    def authenticated?
      @api_resource.authenticated?
    end

    def subnet_exists?(subnet)
      !(subnet[:message] && subnet[:message].downcase == 'no subnet found')
    end

    def no_free_ip_found?(ip)
      ip[:message] && ip[:message].downcase == 'no free addresses found'
    end

    def group_exists?(group)
      !(group && group[:message] && group[:message].downcase == 'not found')
    end

    def no_groups_found?(groups)
      groups[:message] && groups[:message].downcase == 'no sections available'
    end

    def no_subnets_found?(subnets)
      subnets[:message] && subnets[:message].downcase == 'no subnets found'
    end

    def groups_supported?
      true
    end

    private

    # Called when next available IP from external IPAM has been cached by another user/host, but
    # not actually persisted in external IPAM. Will increment the IP(MAX_RETRIES times), and
    # see if it is available in external IPAM.
    def find_new_ip(subnet_id, ip, mac, cidr, group_name)
      found_ip = nil
      temp_ip = ip
      retry_count = 0

      loop do
        new_ip = increment_ip(temp_ip)
        ipam_ip = ip_exists?(new_ip, subnet_id)

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
