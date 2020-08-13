require 'sinatra'
require 'net/http'
require 'json'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/phpipam/phpipam_client'
require 'smart_proxy_ipam/netbox/netbox_client'
require 'smart_proxy_ipam/ipam_helper'

module Proxy::Ipam
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers
    helpers IpamHelper

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
    get '/:provider/subnet/:address/:prefix/next_ip' do
      content_type :json

      begin
        validate_required_params!([:provider, :address, :prefix, :mac], params)
        provider = get_instance(params[:provider])
        mac = params[:mac]
        cidr = params[:address] + '/' + params[:prefix]
        group_name = params[:group]

        if group_name
          group = provider.get_group(group_name)
          halt 500, {error: "Groups are not supported"}.to_json unless provider.groups_supported?
          halt 404, {error: "No group #{group_name} found"}.to_json unless provider.group_exists?(group)
          subnet = provider.get_subnet(cidr, group[:data][:id])
        else
          subnet = provider.get_subnet(cidr)
        end

        halt 404, {error: "No subnets found"}.to_json unless provider.subnet_exists?(subnet)
        next_ip = provider.get_next_ip(subnet[:data][:id], mac, cidr, group_name)
        halt 404, {error: "There are no free IP's in subnet #{cidr}"}.to_json if provider.no_free_ip_found?(next_ip)
        next_ip.to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
      end
    end

    # Gets the subnet from External IPAM
    # 
    # Inputs:   1. provider:  The external IPAM provider(e.g. "phpipam", "netbox")
    #           2. address:   Network address of the subnet
    #           3. prefix:    Network prefix(e.g. 24)
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
    get '/:provider/subnet/:address/:prefix' do
      content_type :json

      begin
        validate_required_params!([:provider, :address, :prefix], params)
        provider = get_instance(params[:provider])
        subnet = provider.get_subnet(params[:address] + '/' + params[:prefix])
        halt 404, {error: errors[:no_subnet]}.to_json unless subnet_exists?(subnet)
        subnet.to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
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
    #       {"data": []}
    # 
    #   Response if groups are not supported:   
    #   ===========================
    #     Http Code:     500 
    #     JSON Response:
    #       {"error": "Groups are not supported"}
    get '/:provider/groups' do
      content_type :json

      begin
        validate_required_params!([:provider], params)
        provider = get_instance(params[:provider])
        halt 500, {error: errors[:groups_not_supported]}.to_json unless provider.groups_supported?
        groups = provider.get_groups
        return {:data => []}.to_json if provider.no_groups_found?(groups)
        groups.to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
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
    get '/:provider/groups/:group' do
      content_type :json 

      begin
        validate_required_params!([:provider, :group], params)
        provider = get_instance(params[:provider])
        group = provider.get_group(params[:group])
        halt 500, {error: errors[:groups_not_supported]}.to_json unless provider.groups_supported?
        halt 404, {error: errors[:no_group]}.to_json unless provider.group_exists?(group)
        group.to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
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
    get '/:provider/groups/:group/subnets' do
      content_type :json 

      begin
        validate_required_params!([:provider, :group], params)
        provider = get_instance(params[:provider])
        group = provider.get_group(params[:group])
        halt 500, {error: errors[:groups_not_supported]}.to_json unless provider.groups_supported?
        halt 404, {error: errors[:no_group]}.to_json unless provider.group_exists?(group)
        subnets = provider.get_subnets(group[:data][:id].to_s, false)
        halt 404, {error: errors[:no_subnets_in_group]}.to_json if provider.no_subnets_found?(subnets)
        subnets.to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
      end
    end

    # Checks whether an IP address has already been taken in External IPAM.
    #
    # Inputs: 1. provider:  The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:   The network address of the IPv4 or IPv6 subnet.
    #         3. prefix:    The subnet prefix(e.g. 24)
    #         4. ip:        IP address to be queried
    #         5. group:     The name of the External IPAM Group
    #
    # Returns: JSON object with 'exists' field being either true or false
    # 
    # Example: 
    #   Response if exists: 
    #   ===========================
    #     Http Code:     200 
    #     JSON Response: 
    #       {"data": true}
    #
    #   Response if not exists:
    #   ===========================
    #     Http Code:     404
    #     JSON Response: 
    #       {"data": false}
    get '/:provider/subnet/:address/:prefix/:ip' do
      content_type :json 

      begin
        validate_required_params!([:provider, :address, :prefix, :ip], params)
        
        ip = params[:ip]
        cidr = params[:address] + '/' + params[:prefix]
        group_name = params[:group]
        provider = get_instance(params[:provider])

        halt 500, {error: errors[:groups_not_supported]}.to_json unless provider.groups_supported?

        if group_name
          group = provider.get_group(group_name)
          subnet = provider.get_subnet(cidr, group[:data][:id])
        else
          subnet = provider.get_subnet(cidr)
        end

        halt 404, {error: errors[:no_subnet]}.to_json unless provider.subnet_exists?(subnet)
        ip_addr = provider.ip_exists(ip, subnet[:data][:id])
        puts "============="
        puts "ip_addr: " + ip_addr.to_json
        puts "============="
        halt 404, {error: errors[:no_ip]}.to_json if provider.ip_not_found?(ip_addr)

        ip_addr.to_json
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
      end
    end

    # Adds an IP address to the specified subnet for the specified IPAM provider
    #
    # Params: 1. provider:  The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:   The network address of the IPv4 or IPv6 subnet.
    #         3. prefix:    The subnet prefix(e.g. 24)
    #         4. ip:        IP address to be added
    #
    # Returns: Hash with "message" on success, or hash with "error" 
    # 
    # Examples:
    #   Response if success: 
    #     IPv4: {"message":"IP 100.10.10.123 added to subnet 100.10.10.0/24 successfully."}
    #     IPv6: {"message":"IP 2001:db8:abcd:12::3 added to subnet 2001:db8:abcd:12::/124 successfully."}
    #   Response if :error =>   
    #     {"error":"The specified subnet does not exist in <PROVIDER>."}
    post '/:provider/subnet/:address/:prefix/:ip' do
      content_type :json

      begin
        validate_required_params!([:provider, :address, :ip, :prefix], params)

        ip = params[:ip]
        cidr = params[:address] + '/' + params[:prefix]
        group = URI.escape(params[:group])
        provider = get_instance(params[:provider])
        subnet = JSON.parse(provider.get_subnet(cidr, group))

        return {:error => subnet['error']}.to_json if no_subnets_found?(subnet)

        response = provider.add_ip_to_subnet(ip, subnet['data']['id'], 'Address auto added by Foreman')
        add_ip = JSON.parse(response.body)

        if add_ip['message'] && add_ip['message'] == "Address created"
          return Net::HTTPCreated.new('HTTP/1.1', 201, 'Created').to_json
        else
          return {:error => add_ip['message']}.to_json
        end
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
      end
    end

    # Deletes IP address from a given subnet
    #
    # Params: 1. provider:  The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:   The network address of the IPv4 or IPv6 subnet.
    #         3. prefix:    The subnet prefix(e.g. 24)
    #         4. ip:        IP address to be deleted
    #
    # Returns: JSON object
    # 
    # Example:
    #   Response if success: 
    #     {"code": 200, "success": true, "message": "Address deleted", "time": 0.017}
    #   Response if :error =>   
    #     {"code": 404, "success": 0, "message": "Address does not exist", "time": 0.008}
    delete '/:provider/subnet/:address/:prefix/:ip' do
      content_type :json

      begin
        validate_required_params!([:provider, :address, :ip, :prefix], params)

        ip = params[:ip]
        cidr = params[:address] + '/' + params[:prefix]
        group_name = URI.escape(params[:group])
        provider = get_instance(params[:provider])
        subnet = JSON.parse(provider.get_subnet(cidr, group_name))
        
        return {:error => subnet['error']}.to_json if no_subnets_found?(subnet)

        response = provider.delete_ip_from_subnet(ip, subnet['data']['id'])
        delete_ip = JSON.parse(response.body)

        if delete_ip['message'] && delete_ip['message'] == "Address deleted"
          return Net::HTTPOK.new('HTTP/1.1', 200, 'Address Deleted').to_json
        else
          return {:error => delete_ip['message']}.to_json
        end
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
      end
    end

    # Checks whether a subnet exists in a specific group.
    #
    # Params: 1. provider:  The external IPAM provider(e.g. "phpipam", "netbox")
    #         2. address:   The network address of the IPv4 or IPv6 subnet.
    #         3. prefix:    The subnet prefix(e.g. 24)
    #         4. group:     The name of the group
    #
    # Returns: JSON object with 'data' field is exists, otherwise field with 'error'
    # 
    # Example: 
    #   Response if exists: 
    #     {"code":200,"success":true,"data":{"id":"147","subnet":"172.55.55.0","mask":"29","sectionId":"84","description":null,"linked_subnet":null,"firewallAddressObject":null,"vrfId":"0","masterSubnetId":"0","allowRequests":"0","vlanId":"0","showName":"0","device":"0","permissions":"[]","pingSubnet":"0","discoverSubnet":"0","resolveDNS":"0","DNSrecursive":"0","DNSrecords":"0","nameserverId":"0","scanAgent":"0","customer_id":null,"isFolder":"0","isFull":"0","tag":"2","threshold":"0","location":"0","editDate":null,"lastScan":null,"lastDiscovery":null,"calculation":{"Type":"IPv4","IP address":"\/","Network":"172.55.55.0","Broadcast":"172.55.55.7","Subnet bitmask":"29","Subnet netmask":"255.255.255.248","Subnet wildcard":"0.0.0.7","Min host IP":"172.55.55.1","Max host IP":"172.55.55.6","Number of hosts":"6","Subnet Class":false}},"time":0.009}
    #   Response if not exists:
    #     {"code":404,"error":"No subnet 172.66.66.0/29 found in section :group"}
    get '/:provider/group/:group/subnet/:address/:prefix' do
      content_type :json 

      begin
        validate_required_params!([:provider, :address, :prefix, :group], params)
        cidr = params[:address] + '/' + params[:prefix]
        provider = get_instance(params[:provider])
        provider.get_subnet_by_group(cidr, params[:group])
      rescue RuntimeError => e
        logger.warn(e.message)
        halt 500, {error: e.message}.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.warn(errors[:no_connection])
        halt 500, {error: errors[:no_connection]}.to_json
      end
    end
  end
end
