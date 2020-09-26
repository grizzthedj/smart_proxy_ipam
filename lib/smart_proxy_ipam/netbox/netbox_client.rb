require 'yaml'
require 'json'
require 'net/http'
require 'uri'
require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_helper'
require 'smart_proxy_ipam/ipam_validator'
require 'smart_proxy_ipam/api_resource'
require 'smart_proxy_ipam/ip_cache'

module Proxy::Netbox
  # Implementation class for External IPAM provider Netbox
  class NetboxClient
    include Proxy::Log
    include Proxy::Ipam::IpamHelper
    include Proxy::Ipam::IpamValidator

    @ip_cache = nil

    def initialize(conf)
      @api_base = "#{conf[:url]}/api/"
      @token = conf[:token]
      @api_resource = Proxy::Ipam::ApiResource.new(api_base: @api_base, token: 'Token ' + @token)
      @ip_cache = Proxy::Ipam::IpCache.new(provider: 'netbox')
    end

    def get_ipam_subnet(cidr, group_name = nil)
      if group_name.nil?
        get_ipam_subnet_by_cidr(cidr)
      else
        group_id = get_group_id(group_name)
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
      raise { 'Groups are not supported' }.to_json unless groups_supported?
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
      return nil if json_body.empty?
      ip = json_body[0]['address'].split('/').first
      cache_next_ip(@ip_cache, ip, mac, cidr, subnet[:id], group_name)
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
  end
end
