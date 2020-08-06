require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/netbox/netbox_client'
require 'smart_proxy_ipam/netbox/netbox_helper'

module Proxy::Netbox
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers NetboxHelper

    def provider
      @provider ||= begin
                      NetboxClient.new
                    end
    end

    # Gets the next available IP address based on a given subnet
    #
    # Inputs:   address:   Network address of the subnet(e.g. 100.55.55.0)
    #           prefix:    Network prefix(e.g. 24)
    #
    # Returns: Hash with next available IP address in "data", or hash with "message" containing
    #          error message from NetBox.
    #
    # Response if success:
    #   {"code": 200, "success": true, "data": "100.55.55.3", "time": 0.012}
    get '/subnet/:address/:prefix/next_ip' do
      content_type :json

      validate_required_params!([:address, :prefix, :mac], params)
      cidr = validate_cidr!(params[:address], params[:prefix])

      mac = params[:mac]
      group = params[:group]

      begin
        subnet = provider.get_subnet(cidr)
        check_subnet_exists!(subnet)

        provider.get_next_ip(subnet['data']['id'], mac, group, cidr).to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, { error: e.message }.to_json
      end
    end

    # Returns an array of subnets from External IPAM matching the given subnet.
    #
    # Params:  1. subnet:           The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24",
    #                               IPv6 - "2001:db8:abcd:12::/124")
    #          2. group(optional):  The name of the External IPAM group containing the subnet.
    #
    # Returns: A subnet on success, or a hash with an "error" key on failure.
    #
    # Responses from Proxy plugin:
    #   Response if subnet(s) exists:
    #     {"data": {"subnet": "44.44.44.0", "description": "", "mask":"29"}}
    #   Response if subnet not exists:
    #     {"error": "No subnets found"}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM server"}
    get '/subnet/:address/:prefix' do
      content_type :json

      validate_required_params!([:address, :prefix], params)
      cidr = validate_cidr!(params[:address], params[:prefix])

      begin
        subnet = provider.get_subnet(cidr)
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, { error: e.message }.to_json
      end

      status 404 unless subnet
      subnet.to_json
    end

    # Get a list of groups from External IPAM. A group is analagous to a 'section' in phpIPAM, and
    # is a logical grouping of subnets/ips.
    #
    # Params: None
    #
    # Returns: An array of groups on success, or a hash with a "error" key
    #          containing error on failure.
    #
    # Responses from Proxy plugin:
    #   Response if success:
    #     {"data": [
    #       {name":"Test Group","description": "A Test Group"},
    #       {name":"Awesome Group","description": "A totally awesome Group"}
    #     ]}
    #   Response if no groups exist:
    #     {"data": []}
    #   Response if groups are not supported:
    #     {"error": "Groups are not supported"}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM server"}
    get '/groups' do
      content_type :json
      return { :error => "Groups are not supported" }.to_json
    end

    # Get a group from External IPAM. A group is analagous to a 'section' in phpIPAM, and
    # is a logical grouping of subnets/ips.
    #
    # Params: group: The name of the External IPAM group
    #
    # Returns: An External IPAM group on success, or a hash with an "error" key on failure.
    #
    # Responses from Proxy plugin:
    #   Response if success:
    #     {"data": {"name":"Awesome Section", "description": "Awesome Section"}}
    #   Response if group doesn't exist:
    #     {"error": "Not found"}
    #   Response if groups are not supported:
    #     {"error": "Groups are not supported"}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM server"}
    get '/groups/:group' do
      content_type :json
      return { :error => "Groups are not supported" }.to_json
    end

    # Get a list of subnets for the given External IPAM group.
    #
    # Params:  1. group:  The name of the External IPAM group containing the subnet.
    #
    # Returns: An array of subnets on success, or a hash with an "error" key on failure.
    #
    # Responses from Proxy plugin:
    #   Response if success: {"data": [
    #     {subnet":"100.10.10.0","mask":"24","description":"Test Subnet 1"},
    #     {subnet":"100.20.20.0","mask":"24","description":"Test Subnet 2"}
    #   ]}
    #   Response if no subnets exist in section.
    #     {"data": []}
    #   Response if section not found:
    #     {"error": "Group not found in External IPAM"}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM"}
    get '/groups/:group/subnets' do
      content_type :json
      return { :error => "Groups are not supported" }.to_json
    end

    # Checks whether an IP address has already been reserved in External IPAM.
    #
    # Inputs: 1. ip:               IP address to be checked
    #         2. subnet:           The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24",
    #                              IPv6 - "2001:db8:abcd:12::/124")
    #         3. group(optional):  The name of the External IPAM group containing the subnet to pull IP from
    #
    # Returns: true if IP exists in External IPAM, otherwise false.
    #
    # Responses from Proxy plugin:
    #   Response if IP is already reserved:
    #     Net::HTTPFound
    #   Response if IP address is available
    #     Net::HTTPNotFound
    #   Response if missing required parameters:
    #     {"error": ["A 'cidr' parameter for the subnet must be provided(e.g. 100.10.10.0/24)", "Missing 'ip' parameter. An IPv4 address must be provided(e.g. 100.10.10.22)"]}
    #   Response if subnet not exists:
    #     {"error": "No subnets found"}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM server"}
    get '/subnet/:address/:prefix/:ip' do
      content_type :json

      validate_required_params!([:address, :prefix, :ip], params)
      ip = validate_ip!(params[:ip])
      cidr = validate_cidr!(params[:address], params[:prefix])
      validate_ip_in_cidr!(ip, cidr)

      begin
        subnet = provider.get_subnet(cidr)
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, { error: e.message }.to_json
      end

      check_subnet_exists!(subnet)

      return Net::HTTPFound.new('HTTP/1.1', 200, 'Found').to_json if provider.ip_exists?(ip, subnet['data']['id'])
      return Net::HTTPNotFound.new('HTTP/1.1', 404, 'Not Found').to_json
    end

    # Adds an IP address to the specified subnet in External IPAM. This will reserve the IP in the
    # External IPAM database. If group is specified, the IP will be added to the subnet within the
    # given group.
    #
    # Params: 1. ip:               IP address to be added
    #         2. subnet:           The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24",
    #                              IPv6 - "2001:db8:abcd:12::/124")
    #         3. group(optional):  The name of the External IPAM group containing the subnet.
    #
    # Returns: true if IP was added successfully to External IPAM, otherwise false
    #
    # Responses from Proxy plugin:
    #   Response if success:
    #     Net::HTTPCreated
    #   Response if IP already reserved:
    #     {"error": "IP address already exists"}
    #   Response if subnet error:
    #     {"error": "The specified subnet does not exist in External IPAM."}
    #   Response if missing required params:
    #     {"error": ["A 'cidr' parameter for the subnet must be provided(e.g. 100.10.10.0/24)","Missing 'ip' parameter. An IPv4 address must be provided(e.g. 100.10.10.22)"]}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM server"}
    post '/subnet/:address/:prefix/:ip' do
      content_type :json

      validate_required_params!([:address, :ip, :prefix], params)
      ip = validate_ip!(params[:ip])
      cidr = validate_cidr!(params[:address], params[:prefix])
      validate_ip_in_cidr!(ip, cidr)

      begin
        subnet = provider.get_subnet(cidr)
        check_subnet_exists!(subnet)

        add_ip = provider.add_ip_to_subnet(ip, params[:prefix], 'Address auto added by Foreman')
        halt 500, add_ip.to_json unless add_ip.nil?
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, { error: e.message }.to_json
      end

      return Net::HTTPCreated.new('HTTP/1.1', 201, 'Created').to_json
    end

    # Deletes an IP address from a given subnet in External IPAM.
    #
    # Inputs: 1. ip:               IP address to be freed up
    #         2. subnet:           The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24",
    #                              IPv6 - "2001:db8:abcd:12::/124")
    #         3. group(optional):  The name of the External IPAM group containing the subnet.
    #
    # Returns: true if IP is deleted successfully from External IPAM, otherwise false.
    #
    # Proxy responses:
    #   Response if success:
    #     Net::HTTPOK
    #   Response if subnet error:
    #     {"error": "The specified subnet does not exist in External IPAM."}
    #   Response if IP already deleted:
    #     {"error": "No addresses found"}
    #   Response if can't connect to External IPAM server
    #     {"error": "Unable to connect to External IPAM server"}
    delete '/subnet/:address/:prefix/:ip' do
      content_type :json

      validate_required_params!([:address, :prefix, :ip], params)
      ip = validate_ip!(params[:ip])
      cidr = validate_cidr!(params[:address], params[:prefix])
      validate_ip_in_cidr!(ip, cidr)

      begin
        subnet = provider.get_subnet(cidr)
        check_subnet_exists!(subnet)

        delete_ip = provider.delete_ip_from_subnet(ip)
        halt 500, delete_ip.to_json unless delete_ip.nil?
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, { error: e.message }.to_json
      end

      return Net::HTTPOK.new('HTTP/1.1', 200, 'OK').to_json
    end

    # Gets a subnet from a specific External IPAM group.
    #
    # Inputs: 1. subnet: The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24", IPv6 - "2001:db8:abcd:12::/124")
    #         2. group: The name of the External IPAM group containing the subnet.
    #
    # Returns: A subnet with a "data" key, or a hash with a "message" key containing error.
    #
    # Proxy responses:
    #   Response if exists:
    #     {"data": {"subnet":"172.55.55.0", "mask":"24", "description":"My subnet"}
    #   Response if not exists:
    #     {"error": "No subnet 172.55.66.0/29 found in section '<:group>'"}
    get '/group/:group/subnet/:address/:prefix' do
      content_type :json
      return { :error => "Groups are not supported" }.to_json
    end
  end
end
