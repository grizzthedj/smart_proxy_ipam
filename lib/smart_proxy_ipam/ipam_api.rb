require 'sinatra'
require 'net/http'
require 'json'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/phpipam/phpipam_client'
require 'smart_proxy_ipam/netbox/netbox_client'
require 'smart_proxy_ipam/ipam_helper'

module Proxy::Ipam
  # Generic API for External IPAM interactions
  class Api < ::Sinatra::Base
    extend Proxy::DHCP::DependencyInjection
    
    include ::Proxy::Log
    helpers ::Proxy::Helpers
    helpers IpamHelper
    # authorize_with_trusted_hosts
    # authorize_with_ssl_client
    inject_attr :ipam_provider, :server

    # Gets the next available IP address based on a given External IPAM subnet
    #
    # Inputs:   1. provider:         The external IPAM provider(e.g. "phpipam", "netbox")
    #           2. address:          Network address of the subnet(e.g. 100.55.55.0)
    #           3. prefix:           Network prefix(e.g. 24)
    #           4. group(optional):  The External IPAM group
    #
    # Returns:
    #   Response if success:
    #   ======================
    #     Http Code:     200
    #     JSON Response:
    #       {"data": "100.55.55.3"}
    #
    #   Response if missing parameter(e.g. 'mac')
    #   ======================
    #     Http Code:     400
    #     JSON Response:
    #       {"error": ["A 'mac' address must be provided(e.g. 00:0a:95:9d:68:10)"]}
    #
    #   Response if no free ip's available
    #   ======================
    #     Http Code:     404
    #     JSON Response:
    #       {"error": "There are no free IP's in subnet 100.55.55.0/24"}
    ['/:provider/subnet/:address/:prefix/next_ip', '/subnet/:address/:prefix/next_ip'].each do |path|
      get path do
        content_type :json

        begin
          validate_presence_of!([:address, :prefix, :mac], params)

          mac = get_request_mac(params)
          cidr = get_request_cidr(params)
          provider = get_provider_instance(params[:provider])
          group_name = get_request_group(params, provider)
          subnet = get_ipam_subnet(provider, group_name, cidr)

          halt 404, { error: errors[:no_subnet] }.to_json unless provider.subnet_exists?(subnet)
          next_ip = provider.get_next_ip(subnet[:id], mac, cidr, group_name)
          halt 404, { error: errors[:no_free_ips] }.to_json if provider.no_free_ip_found?(next_ip)
          next_ip.to_json
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Gets the subnet from External IPAM
    #
    # Inputs:   1. provider:         The external IPAM provider(e.g. "phpipam", "netbox")
    #           2. address:          Network address of the subnet
    #           3. prefix:           Network prefix(e.g. 24)
    #           4. group(optional):  The name of the External IPAM group
    #
    # Returns:
    #   Response if subnet exists:
    #   ===========================
    #     Http Code:     200
    #     JSON Response:
    #       {"data": {
    #         "id": "33",
    #         "subnet": "10.20.30.0",
    #         "description": "Subnet description",
    #         "mask": "29"}
    #       }
    #
    #   Response if subnet does not exist:
    #   ===========================
    #     Http Code:     404
    #     JSON Response:
    #       {"error": "No subnets found"}
    ['/:provider/subnet/:address/:prefix', '/subnet/:address/:prefix'].each do |path|
      get path do
        content_type :json

        begin
          validate_presence_of!([:address, :prefix], params)

          cidr = get_request_cidr(params)
          provider = get_provider_instance(params[:provider])
          group_name = get_request_group(params, provider)
          subnet = get_ipam_subnet(provider, group_name, cidr)

          halt 404, { error: errors[:no_subnet] }.to_json unless provider.subnet_exists?(subnet)
          subnet.to_json
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Get a list of groups from External IPAM
    #
    # Inputs:   1. provider:    The External IPAM provider(e.g. "phpipam", "netbox")
    #
    # Returns:
    #   Response if success:
    #   ===========================
    #     Http Code:     200
    #     JSON Response:
    #       {"data": [
    #         {"id": "1", "name": "Group 1", "description": "This is group 1"},
    #         {"id": "2", "name": "Group 2", "description": "This is group 2"}
    #       ]}
    #
    #   Response if no groups exist:
    #   ===========================
    #     Http Code:     404
    #     JSON Response:
    #       {"error": "Groups are not supported"}
    #
    #   Response if groups are not supported:
    #   ===========================
    #     Http Code:     500
    #     JSON Response:
    #       {"error": "Groups are not supported"}
    ['/:provider/groups', '/groups'].each do |path|
      get path do
        content_type :json

        begin
          provider = get_provider_instance(params[:provider])
          halt 500, { error: errors[:groups_not_supported] }.to_json unless provider.groups_supported?
          groups = provider.get_ipam_groups
          halt 404, { error: errors[:no_groups] }.to_json if provider.no_groups_found?(groups)
          groups.to_json
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Get a group from External IPAM
    #
    # Inputs:   1. provider:    The External IPAM provider(e.g. "phpipam", "netbox")
    #           2. group:       The name of the External IPAM group
    #
    # Returns:
    #   Response if success:
    #   ===========================
    #     Http Code:     200
    #     JSON Response:
    #       {"data": {"id": "1", "name": "Group 1", "description": "This is group 1"}}
    #
    #   Response if group not found:
    #   ===========================
    #     Http Code:     404
    #     JSON Response:
    #       {"error": "Group not Found"}
    #
    #   Response if groups are not supported:
    #   ===========================
    #     Http Code:     500
    #     JSON Response:
    #       {"error": "Groups are not supported"}
    ['/:provider/groups/:group', '/groups/:group'].each do |path|
      get path do
        content_type :json

        begin
          validate_presence_of!([:group], params)

          provider = get_provider_instance(params[:provider])
          group_name = get_request_group(params, provider)
          group = provider.get_ipam_group(group_name)

          halt 404, { error: errors[:no_group] }.to_json unless provider.group_exists?(group)
          group.to_json
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Get a list of subnets for a given External IPAM group
    #
    # Input:   1. provider:      The external IPAM provider(e.g. "phpipam", "netbox")
    #          2. group:         The name of the External IPAM group
    #
    # Returns:
    #   Response if success:
    #   ===========================
    #     Http Code:     200
    #     JSON Response:
    #       {"data":[
    #         {"subnet":"10.20.30.0","mask":"29","description":"This is a subnet"},
    #         {"subnet":"40.50.60.0","mask":"29","description":"This is another subnet"}
    #       ]}
    #
    #   Response if no subnets exist in group:
    #   ===========================
    #     Http Code:     404
    #     JSON Response:
    #       {"error": "No subnets found in External IPAM group"}
    #
    #   Response if groups are not supported:
    #   ===========================
    #     Http Code:     500
    #     JSON Response:
    #       {"error": "Groups are not supported"}
    ['/:provider/groups/:group/subnets', '/groups/:group/subnets'].each do |path|
      get path do
        content_type :json

        begin
          validate_presence_of!([:group], params)

          provider = get_provider_instance(params[:provider])
          group_name = get_request_group(params, provider)
          group = provider.get_ipam_group(group_name)

          halt 404, { error: errors[:no_group] }.to_json unless provider.group_exists?(group)
          subnets = provider.get_ipam_subnets(group[:id].to_s, false)
          halt 404, { error: errors[:no_subnets_in_group] }.to_json if provider.no_subnets_found?(subnets)
          subnets.to_json
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Checks whether an IP address has already been taken in External IPAM
    #
    # Inputs: 1. provider:        The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:         The network address of the IPv4 or IPv6 subnet.
    #         3. prefix:          The subnet prefix(e.g. 24)
    #         4. ip:              IP address to be queried
    #         5. group(optional): The name of the External IPAM Group, containing the subnet to check
    #
    # Returns:
    #   Response if exists:
    #   ===========================
    #     Http Code:  200
    #     Response:   true
    #
    #   Response if not exists:
    #   ===========================
    #     Http Code:      200
    #     JSON Response:  false
    ['/:provider/subnet/:address/:prefix/:ip', '/subnet/:address/:prefix/:ip'].each do |path|
      get path do
        content_type :json

        begin
          validate_presence_of!([:address, :prefix, :ip], params)

          ip = get_request_ip(params)
          cidr = get_request_cidr(params)
          provider = get_provider_instance(params[:provider])
          group_name = get_request_group(params, provider)
          subnet = get_ipam_subnet(provider, group_name, cidr)

          validate_ip_in_cidr!(ip, cidr)

          halt 404, { error: errors[:no_subnet] }.to_json unless provider.subnet_exists?(subnet)
          ip_exists = provider.ip_exists?(ip, subnet[:id])
          halt 200, ip_exists.to_json
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Adds an IP address to the specified subnet for the specified IPAM provider
    #
    # Params: 1. provider:        The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:         The network address of the IPv4 or IPv6 subnet
    #         3. prefix:          The subnet prefix(e.g. 24)
    #         4. ip:              IP address to be added
    #         5. group(optional): The name of the External IPAM Group, containing the subnet to add ip to
    #
    # Returns:
    #   Response if added successfully:
    #   ===========================
    #     Http Code:  201
    #     Response:   Empty
    #
    #   Response if not added successfully:
    #   ===========================
    #     Http Code:  500
    #     JSON Response:
    #       {"error": "Unable to add IP to External IPAM"}
    ['/:provider/subnet/:address/:prefix/:ip', '/subnet/:address/:prefix/:ip'].each do |path|
      post path do
        content_type :json

        begin
          validate_presence_of!([:address, :ip, :prefix], params)

          ip = get_request_ip(params)
          cidr = get_request_cidr(params)
          provider = get_provider_instance(params[:provider])
          group_name = get_request_group(params, provider)
          subnet = get_ipam_subnet(provider, group_name, cidr)

          validate_ip_in_cidr!(ip, cidr)

          halt 404, { error: errors[:no_subnet] }.to_json unless provider.subnet_exists?(subnet)
          ip_added = provider.add_ip_to_subnet(ip, subnet[:id], 'Address auto added by Foreman')
          halt 500, ip_added.to_json unless ip_added.nil?
          halt 201
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end

    # Deletes IP address from a given subnet
    #
    # Params: 1. provider:        The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:         The network address of the IPv4 or IPv6 subnet
    #         3. prefix:          The subnet prefix(e.g. 24)
    #         4. ip:              IP address to be deleted
    #         5. group(optional): The name of the External IPAM Group, containing the subnet to delete ip from
    #
    # Returns:
    #   Response if deleted successfully:
    #   ===========================
    #     Http Code:  200
    #     Response:   Empty
    #
    #   Response if not added successfully:
    #   ===========================
    #     Http Code:  500
    #     JSON Response:
    #       {"error": "Unable to delete IP from External IPAM"}
    ['/:provider/subnet/:address/:prefix/:ip', '/subnet/:address/:prefix/:ip'].each do |path|
      delete path do
        content_type :json

        begin
          validate_presence_of!([:address, :ip, :prefix], params)

          ip = get_request_ip(params)
          cidr = get_request_cidr(params)
          group_name = URI.escape(params[:group]) if params[:group]
          provider = get_provider_instance(params[:provider])
          subnet = get_ipam_subnet(provider, group_name, cidr)

          validate_ip_in_cidr!(ip, cidr)

          halt 404, { error: errors[:no_subnet] }.to_json unless provider.subnet_exists?(subnet)
          ip_deleted = provider.delete_ip_from_subnet(ip, subnet[:id])
          halt 500, ip_deleted.to_json unless ip_deleted.nil?
          halt 200
        rescue RuntimeError => e
          logger.warn(e.message)
          halt 500, { error: e.message }.to_json
        rescue Errno::ECONNREFUSED, Errno::ECONNRESET
          logger.warn(errors[:no_connection])
          halt 500, { error: errors[:no_connection] }.to_json
        end
      end
    end
  end
end
