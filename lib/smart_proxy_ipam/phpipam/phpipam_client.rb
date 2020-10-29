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
      if group_name.nil? || group_name.empty?
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
        subnet_cidr = "#{subnet[:subnet]}/#{subnet[:mask]}"
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
      raise ERRORS[:no_group] if json_body['data'].nil?

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
      return [] if json_body['data'].nil?

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
      raise ERRORS[:no_group] if group.nil?
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
      raise ERRORS[:no_subnet] if subnet.nil?
      response = @api_resource.get("subnets/#{subnet[:id]}/first_free/")
      json_body = JSON.parse(response.body)
      return { error: json_body['message'] } if json_body['message']
      ip = json_body['data']
      next_ip = cache_next_ip(@ip_cache, ip, mac, cidr, subnet[:id], group_name)
      { data: next_ip }
    end

    def groups_supported?
      true
    end

    def authenticated?
      !@token.nil?
    end

    private

    def authenticate
      auth_uri = URI("#{@api_base}/user/")
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
