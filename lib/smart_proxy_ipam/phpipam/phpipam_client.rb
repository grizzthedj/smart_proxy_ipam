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
require 'smart_proxy_ipam/ipam_validator'
require 'smart_proxy_ipam/api_resource'
require 'smart_proxy_ipam/ip_cache'

module Proxy::Phpipam
  # Implementation class for External IPAM provider phpIPAM
  class PhpipamClient
    include Proxy::Log
    include Proxy::Ipam::IpamHelper
    include Proxy::Ipam::IpamValidator

    @ip_cache = nil

    def initialize(conf)
      @conf = conf
      @api_base = "#{@conf[:url]}/api/#{@conf[:user]}/"
      @token = authenticate
      @api_resource = Proxy::Ipam::ApiResource.new(api_base: @api_base, token: @token, auth_header: 'Token')
      @ip_cache = Proxy::Ipam::IpCache.new(provider: 'phpipam')
    end

    def get_ipam_subnet(cidr, group_name = nil)
      if group_name.nil?
        get_ipam_subnet_by_cidr(cidr)
      else
        group = get_ipam_group(group_name)
        get_ipam_subnet_by_group(cidr, group[:id])
      end
    end

    def get_ipam_subnet_by_group(cidr, group_id)
      subnets = get_ipam_subnets(group_id)
      return nil if subnets.nil?
      subnet_id = nil

      subnets.each do |subnet|
        subnet_cidr = subnet[:subnet] + '/' + subnet[:mask]
        subnet_id = subnet[:id] if subnet_cidr == cidr
      end

      return nil if subnet_id.nil?
      response = @api_resource.get("subnets/#{subnet_id}/")
      json_body = JSON.parse(response.body)

      data = {
        id: json_body['data']['id'],
        subnet: json_body['data']['subnet'],
        mask: json_body['data']['mask'],
        description: json_body['data']['description']
      }

      return data if json_body['data']
    end

    def get_ipam_subnet_by_cidr(cidr)
      subnet = @api_resource.get("subnets/cidr/#{cidr}")
      json_body = JSON.parse(subnet.body)
      return nil if json_body['data'].nil?

      data = {
        id: json_body['data'][0]['id'],
        subnet: json_body['data'][0]['subnet'],
        mask: json_body['data'][0]['mask'],
        description: json_body['data'][0]['description']
      }

      return data if json_body['data']
    end

    def get_ipam_group(group_name)
      return nil if group_name.nil?
      group = @api_resource.get("sections/#{group_name}/")
      json_body = JSON.parse(group.body)
      raise errors[:no_group] if json_body['data'].nil?

      data = {
        id: json_body['data']['id'],
        name: json_body['data']['name'],
        description: json_body['data']['description']
      }

      return data if json_body['data']
    end

    def get_ipam_groups
      groups = @api_resource.get('sections/')
      json_body = JSON.parse(groups.body)
      return nil if json_body['data'].nil?

      data = []
      json_body['data'].each do |group|
        data.push({
          id: group['id'],
          name: group['name'],
          description: group['description']
        })
      end

      return data if json_body['data']
    end

    def get_ipam_subnets(group_name)
      group = get_ipam_group(group_name)
      raise errors[:no_group] if group.nil?
      subnets = @api_resource.get("sections/#{group[:id]}/subnets/")
      json_body = JSON.parse(subnets.body)
      return nil if json_body['data'].nil?

      data = []
      json_body['data'].each do |subnet|
        data.push({
          id: subnet['id'],
          subnet: subnet['subnet'],
          mask: subnet['mask'],
          description: subnet['description']
        })
      end

      return data if json_body['data']
    end

    def ip_exists?(ip, subnet_id, _group_name)
      ip = @api_resource.get("subnets/#{subnet_id}/addresses/#{ip}/")
      json_body = JSON.parse(ip.body)
      json_body['success']
    end

    def add_ip_to_subnet(ip, params)
      data = { subnetId: params[:subnet_id], ip: ip, description: 'Address auto added by Foreman' }
      subnet = @api_resource.post('addresses/', data.to_json)
      json_body = JSON.parse(subnet.body)
      return nil if json_body['code'] == 201
      { error: 'Unable to add IP to External IPAM' }
    end

    def delete_ip_from_subnet(ip, params)
      subnet = @api_resource.delete("addresses/#{ip}/#{params[:subnet_id]}/")
      json_body = JSON.parse(subnet.body)
      return nil if json_body['success']
      { error: 'Unable to delete IP from External IPAM' }
    end

    def get_next_ip(mac, cidr, group_name)
      subnet = get_ipam_subnet(cidr, group_name)
      raise errors[:no_subnet] if subnet.nil?
      response = @api_resource.get("subnets/#{subnet[:id]}/first_free/")
      json_body = JSON.parse(response.body)
      group = group_name.nil? ? '' : group_name
      @ip_cache.set_group(group, {}) if @ip_cache.get_group(group).nil?
      subnet_hash = @ip_cache.get_cidr(group, cidr)
      next_ip = nil

      return { error: json_body['message'] } if json_body['message']

      if subnet_hash&.key?(mac.to_sym)
        next_ip = @ip_cache.get_ip(group, cidr, mac)
      else
        new_ip = json_body['data']
        ip_not_in_cache = subnet_hash.nil? ? true : !subnet_hash.to_s.include?(new_ip.to_s)

        if ip_not_in_cache
          next_ip = new_ip.to_s
          @ip_cache.add(new_ip, mac, cidr, group)
        else
          next_ip = find_new_ip(@ip_cache, subnet[:id], new_ip, mac, cidr, group)
        end

        unless usable_ip(next_ip, cidr)
          return { error: "No free addresses found in subnet #{cidr}. Some available ip's may be cached. Try again in #{@ip_cache.get_cleanup_interval} seconds after cache is cleared." }
        end
      end

      return nil if no_free_ip_found?(next_ip)

      next_ip
    end

    def no_free_ip_found?(ip)
      ip.is_a?(Hash) && ip['message'] && ip['message'].downcase == 'no free addresses found'
    end

    def subnet_exists?(subnet)
      !(subnet[:message] && subnet[:message].downcase == 'no subnet found')
    end

    def groups_supported?
      true
    end

    def authenticated?
      !@token.nil?
    end

    private

    def authenticate
      auth_uri = URI(@api_base + '/user/')
      request = Net::HTTP::Post.new(auth_uri)
      request.basic_auth @conf[:user], @conf[:password]

      response = Net::HTTP.start(auth_uri.hostname, auth_uri.port, use_ssl: auth_uri.scheme == 'https') do |http|
        http.request(request)
      end

      response = JSON.parse(response.body)
      logger.warn(response['message']) if response['message']
      response.dig('data', 'token')
    end
  end
end
