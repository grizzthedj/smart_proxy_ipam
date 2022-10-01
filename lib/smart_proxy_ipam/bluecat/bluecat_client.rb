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

module Proxy::Bluecat
  # Implementation class for External IPAM provider Bluecat
  class BluecatClient
    include Proxy::Log
    include Proxy::Ipam::IpamHelper
    include Proxy::Ipam::IpamValidator

    def initialize(conf)
      @api_base = "#{conf[:url]}/Services/REST/v1/"
      @token = authenticate
      @api_resource = Proxy::Ipam::ApiResource.new(api_base: @api_base, token: "#{@token}")
      @ip_cache = Proxy::Ipam::IpCache.instance
      @ip_cache.set_provider_name('bluecat')
    end

    def get_ipam_subnet(cidr, group_name = nil)
      if group_name.nil? || group_name.empty?
        get_ipam_subnet_by_cidr(cidr)
      else
        group_id = get_group_id(group_name)
        get_ipam_subnet_by_group(cidr, group_id)
      end
    end

    def get_ipam_subnet_by_group(cidr, group_id)
      params = URI.encode_www_form({ status: 'active', prefix: cidr, vrf_id: group_id })
      response = @api_resource.get("ipam/prefixes/?#{params}")
      json_body = JSON.parse(response.body)
      return nil if json_body['count'].zero?
      subnet = subnet_from_result(json_body['results'][0])
      return subnet if json_body['results']
    end

    def get_ipam_subnet_by_cidr(cidr)
      network_addr = cidr.split('/')[0]
      params = URI.encode_www_form({ type: 'IP4Network', address: network_addr, containerId: 5 })
      response = @api_resource.get("getIPRangedByIP/?#{params}")
      json_body = JSON.parse(response.body)
      return nil if json_body['count'].zero?
      subnet = subnet_from_result(json_body['results'][0])
      return subnet if json_body['results']
    end

    def get_ipam_groups
      response = @api_resource.get('ipam/vrfs/')
      json_body = JSON.parse(response.body)
      groups = []

      return groups if json_body['count'].zero?

      json_body['results'].each do |group|
        groups.push({
          name: group['name'],
          description: group['description']
        })
      end

      groups
    end

    def get_ipam_group(group_name)
      raise ERRORS[:groups_not_supported] unless groups_supported?
      # TODO: Fix encoding of params in a common way for all providers
      params = URI.encode_www_form({ name: URI.decode(group_name) })
      response = @api_resource.get("ipam/vrfs/?#{params}")
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
      raise ERRORS[:no_group] if group.nil?
      group[:id]
    end

    def get_ipam_subnets(group_name)
      if group_name.nil?
        params = URI.encode_www_form({ status: 'active' })
      else
        group_id = get_group_id(group_name)
        params = URI.encode_www_form({ status: 'active', vrf_id: group_id })
      end

      response = @api_resource.get("ipam/prefixes/?#{params}")
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
      url = "ipam/ip-addresses/?#{URI.encode_www_form({ address: ip })}"
      url += "&#{URI.encode_www_form({ prefix_id: subnet_id })}" unless subnet_id.nil?
      url += "&#{URI.encode_www_form({ vrf_id: group_id })}" unless group_id.nil?
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
        params = URI.encode_www_form({ address: ip })
      else
        group_id = get_group_id(group_name)
        params = URI.encode_www_form({ address: ip, vrf_id: group_id })
      end

      response = @api_resource.get("ipam/ip-addresses/?#{params}")
      json_body = JSON.parse(response.body)

      return { error: ERRORS[:no_ip] } if json_body['count'].zero?

      address_id = json_body['results'][0]['id']
      response = @api_resource.delete("ipam/ip-addresses/#{address_id}/")
      return nil if response.code == '204'
      { error: "Unable to delete #{ip} in External IPAM server" }
    end

    def get_next_ip(mac, cidr, group_name)
      subnet = get_ipam_subnet(cidr, group_name)
      raise ERRORS[:no_subnet] if subnet.nil?
      params = URI.encode_www_form(parentId: subnet['parentId'.to_sym])
      response = @api_resource.get("getNextAvailableIP4Address/?#{params}")
      json_body = JSON.parse(response.body)
      return nil if json_body.empty?
      ip = json_body[0]['address'].split('/').first
      next_ip = cache_next_ip(@ip_cache, ip, mac, cidr, subnet[:id], group_name)
      { data: next_ip }
    end

    def groups_supported?
      false
    end

    def authenticated?
      !@token.nil?
    end

    private

    def authenicate
      auth_uri = URI("#{@api_base}login?username=#{@conf[:user]}&password=#{@conf[:password]}")
      request = Net::HTTP::Get.new(auth_uri)
      request['Content-Type'] = 'application/json'
      response = Net::HTTP.start(auth_uri.hostname, auth_uri.port, use_ssl: auth_uri.scheme == 'https') do |http|
        http.request(request)
      end
      if response.code == '200'
        token = response.body.split()[2] + " " + response.body.split()[3]
      end
    end

    def subnet_from_result(result)
      {
        id: result['id'],
        subnet: result['properties'].split("CIDR=")[1].split("|")[0].split("/").first,
        mask: result['properties'].split("CIDR=")[1].split("|")[0].split("/").last,
        description: result['name']
      }
    end
  end
end
