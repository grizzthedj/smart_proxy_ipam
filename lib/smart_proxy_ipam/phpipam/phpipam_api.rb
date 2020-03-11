require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/phpipam/phpipam_client'
require 'smart_proxy_ipam/phpipam/phpipam_helper'

# TODO: Refactor later to handle multiple IPAM providers. For now, it is 
# just phpIPAM that is supported
module Proxy::Phpipam
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers
    helpers PhpipamHelper

    # Gets the next available IP address based on a given subnet
    # 
    # Inputs:   address:   Network address of the subnet(e.g. 100.55.55.0)
    #           prefix:    Network prefix(e.g. 24)
    # 
    # Returns: Hash with next available IP address in "data", or hash with "message" containing
    #          error message from phpIPAM.
    #
    # Response if success: 
    #   {"code": 200, "success": true, "data": "100.55.55.3", "time": 0.012}
    get '/subnet/:address/:prefix/next_ip' do
      content_type :json

      begin
        err = validate_required_params(["address", "prefix", "mac"], params)
        return err if err.length > 0

        mac = params[:mac]
        cidr = params[:address] + '/' + params[:prefix]
        section_name = params[:group]

        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?

        subnet = JSON.parse(phpipam_client.get_subnet(cidr, section_name))

        return {:code => subnet['code'], :error => subnet['error']}.to_json if no_subnets_found?(subnet)

        ipaddr = phpipam_client.get_next_ip(subnet['data']['id'], mac, cidr, section_name)
        ipaddr_parsed = JSON.parse(ipaddr)

        return {:code => 404, :error => ipaddr_parsed['error']}.to_json if no_free_ip_found?(ipaddr_parsed)

        ipaddr
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Gets the subnet from phpIPAM
    # 
    # Inputs:   address:   Network address of the subnet
    #           prefix:    Network prefix(e.g. 24)
    # 
    # Returns: JSON with "data" key on success, or JSON with "error" key when there is an error
    # 
    # Examples: 
    #   Response if subnet exists:
    #     {
    #       "code":200,"success":true,"data":[{"id":"12","subnet":"100.30.30.0","mask":"24",
    #       "sectionId":"5", "description":"Test Subnet","linked_subnet":null,"firewallAddressObject":null,
    #       "vrfId":"0","masterSubnetId":"0","allowRequests":"0","vlanId":"0","showName":"0","device":"0",
    #       "permissions":"[]","pingSubnet":"0","discoverSubnet":"0","DNSrecursive":"0","DNSrecords":"0",
    #       "nameserverId":"0","scanAgent":"0","isFolder":"0","isFull":"0","tag":"2","threshold":"0",
    #       "location":"0","editDate":null,"lastScan":null,"lastDiscovery":null}],"time":0.009
    #     }
    #
    #   Response if subnet not exists):
    #     {
    #       "code":200,"success":0,"message":"No subnets found","time":0.01
    #     }
    get '/subnet/:address/:prefix' do
      content_type :json

      begin
        err = validate_required_params(["address", "prefix"], params)
        return err if err.length > 0

        cidr = params[:address] + '/' + params[:prefix]

        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?

        phpipam_client.get_subnet(cidr)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Get a list of sections from external ipam
    #
    # Input: None
    # Returns: An array of sections on success, hash with "error" key otherwise
    # Examples
    #   Response if success: [
    #     {"id":"5","name":"Awesome Section","description":"A totally awesome Section","masterSection":"0",
    #      "permissions":"[]","strictMode":"1","subnetOrdering":"default","order":null,
    #      "editDate":"2019-04-19 21:49:55","showVLAN":"1","showVRF":"1","showSupernetOnly":"1","DNS":null}]
    #   ]
    #   Response if :error =>   
    #     {"error":"Unable to connect to phpIPAM server"}
    get '/groups' do
      content_type :json

      begin
        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?

        sections = phpipam_client.get_sections
        return {:code => 200, :data => []}.to_json if no_sections_found?(JSON.parse(sections))

        sections
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Get a single sections from external ipam
    #
    # Input: Section name
    # Returns: A JSON section on success, hash with "error" key otherwise
    # Examples
    #   Response if success: 
    #     {"code":200,"success":true,"data":{"id":"80","name":"Development #1","description":null,
    #      "masterSection":"0","permissions":"[]","strictMode":"1","subnetOrdering":"default","order":null,
    #      "editDate":"2020-02-11 10:57:01","showVLAN":"1","showVRF":"1","showSupernetOnly":"1","DNS":null},"time":0.004}
    #   Response if not found: 
    #     {"code":404,"error":"Not Found"}
    #   Response if :error =>   
    #     {"error":"Unable to connect to phpIPAM server"}
    get '/groups/:group' do
      content_type :json 

      begin
        err = validate_required_params(["group"], params)
        return err if err.length > 0
 
        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?
        
        section = JSON.parse(phpipam_client.get_section(params[:group]))
        return {:code => section['code'], :message => section['message']}.to_json if no_section_found?(section)

        section.to_json
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Get a list of subnets for given external ipam section/group
    #
    # Input: section_name(string). The name of the external ipam section/group
    # Returns: Array of subnets(as json) in "data" key on success, hash with error otherwise
    # Examples:
    #   Response if success: 
    #     {  
    #       "code":200,
    #       "success":true,
    #       "data":[  
    #         {  
    #             "id":"24",
    #             "subnet":"100.10.10.0",
    #             "mask":"24",
    #             "sectionId":"10",
    #             "description":"wrgwgwefwefw",
    #             "linked_subnet":null,
    #             "firewallAddressObject":null,
    #             "vrfId":"0",
    #             "masterSubnetId":"0",
    #             "allowRequests":"0",
    #             "vlanId":"0",
    #             "showName":"0",
    #             "device":"0",
    #             "permissions":"[]",
    #             "pingSubnet":"0",
    #             "discoverSubnet":"0",
    #             "DNSrecursive":"0",
    #             "DNSrecords":"0",
    #             "nameserverId":"0",
    #             "scanAgent":"0",
    #             "isFolder":"0",
    #             "isFull":"0",
    #             "tag":"2",
    #             "threshold":"0",
    #             "location":"0",
    #             "editDate":null,
    #             "lastScan":null,
    #             "lastDiscovery":null,
    #             "usage":{  
    #               "used":"0",
    #               "maxhosts":"254",
    #               "freehosts":"254",
    #               "freehosts_percent":100,
    #               "Offline_percent":0,
    #               "Used_percent":0,
    #               "Reserved_percent":0,
    #               "DHCP_percent":0
    #             }
    #         }
    #       ],
    #       "time":0.012
    #     }
    #   Response if :error =>   
    #     {"error":"Unable to connect to External IPAM server"}
    get '/groups/:group/subnets' do
      content_type :json 

      begin
        err = validate_required_params(["group"], params)
        return err if err.length > 0

        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?

        section = JSON.parse(phpipam_client.get_section(params[:group]))
        return {:code => 404, :error => errors[:no_section]}.to_json if no_section_found?(section)

        phpipam_client.get_subnets(section['data']['id'].to_s, false)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Checks whether an IP address has already been taken in external ipam.
    #
    # Params: 1. address:   The network address of the IPv4 or IPv6 subnet.
    #         2. prefix:    The subnet prefix(e.g. 24)
    #         3. ip:        IP address to be queried
    #
    # Returns: JSON object with 'exists' field being either true or false
    # 
    # Example: 
    #   Response if exists: 
    #     {"ip":"100.20.20.18","exists":true}
    #   Response if not exists:
    #     {"ip":"100.20.20.18","exists":false}
    get '/subnet/:address/:prefix/:ip' do
      content_type :json 

      begin
        err = validate_required_params(["address", "prefix", "ip"], params)
        return err if err.length > 0

        ip = params[:ip]
        cidr = params[:address] + '/' + params[:prefix]
        section_name = params[:group]

        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?
        
        subnet = JSON.parse(phpipam_client.get_subnet(cidr, section_name))
        return {:code => 404, :error => subnet['error']}.to_json if no_subnets_found?(subnet)

        ip_exists = JSON.parse(phpipam_client.ip_exists(ip, subnet['data']['id']))

        if ip_exists['data']
          return {:code => 200, :exists => true}.to_json
        else
          return {:code => 404, :exists => false}.to_json 
        end
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Adds an IP address to the specified subnet
    #
    # Params: 1. address:   The network address of the IPv4 or IPv6 subnet.
    #         2. prefix:    The subnet prefix(e.g. 24)
    #         3. ip:        IP address to be added
    #
    # Returns: Hash with "message" on success, or hash with "error" 
    # 
    # Examples:
    #   Response if success: 
    #     IPv4: {"message":"IP 100.10.10.123 added to subnet 100.10.10.0/24 successfully."}
    #     IPv6: {"message":"IP 2001:db8:abcd:12::3 added to subnet 2001:db8:abcd:12::/124 successfully."}
    #   Response if :error =>   
    #     {"error":"The specified subnet does not exist in phpIPAM."}
    post '/subnet/:address/:prefix/:ip' do
      content_type :json

      begin
        err = validate_required_params(["address", "ip", "prefix"], params)
        return err if err.length > 0

        ip = params[:ip]
        cidr = params[:address] + '/' + params[:prefix]
        section_name = URI.escape(params[:group])

        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?
        
        subnet = JSON.parse(phpipam_client.get_subnet(cidr, section_name))
        return {:code => 404, :error => subnet['error']}.to_json if no_subnets_found?(subnet)

        add_ip = JSON.parse(phpipam_client.add_ip_to_subnet(ip, subnet['data']['id'], 'Address auto added by Foreman'))

        if add_ip['message'] && add_ip['message'] == "Address created"
          return {:code => 200}.to_json
        else
          return {:code => 500, :error => add_ip['message']}.to_json
        end
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Deletes IP address from a given subnet
    #
    # Params: 1. address:   The network address of the IPv4 or IPv6 subnet.
    #         2. prefix:    The subnet prefix(e.g. 24)
    #         3. ip:        IP address to be deleted
    #
    # Returns: JSON object
    # Example:
    #   Response if success: 
    #     {"code": 200, "success": true, "message": "Address deleted", "time": 0.017}
    #   Response if :error =>   
    #     {"code": 404, "success": 0, "message": "Address does not exist", "time": 0.008}
    delete '/subnet/:address/:prefix/:ip' do
      content_type :json

      begin
        err = validate_required_params(["address", "prefix", "ip"], params)
        return err if err.length > 0

        ip = params[:ip]
        cidr = params[:address] + '/' + params[:prefix]
        section_name = URI.escape(params[:group])
        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?

        subnet = JSON.parse(phpipam_client.get_subnet(cidr, section_name))
        return {:code => 404, :error => subnet['error']}.to_json if no_subnets_found?(subnet)

        delete_ip = JSON.parse(phpipam_client.delete_ip_from_subnet(ip, subnet['data']['id']))

        if delete_ip['message'] && delete_ip['message'] == "Address deleted"
          return {:code => 200}.to_json
        else 
          return {:code => 500, :error => delete_ip['message']}.to_json
        end
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end

    # Checks whether a subnet exists in a specific section.
    #
    # Params: 1. address:   The network address of the IPv4 or IPv6 subnet.
    #         2. prefix:    The subnet prefix(e.g. 24)
    #         3. group:     The name of the section
    #
    # Returns: JSON object with 'data' field is exists, otherwise field with 'error'
    # 
    # Example: 
    #   Response if exists: 
    #     {"code":200,"success":true,"data":{"id":"147","subnet":"172.55.55.0","mask":"29","sectionId":"84","description":null,"linked_subnet":null,"firewallAddressObject":null,"vrfId":"0","masterSubnetId":"0","allowRequests":"0","vlanId":"0","showName":"0","device":"0","permissions":"[]","pingSubnet":"0","discoverSubnet":"0","resolveDNS":"0","DNSrecursive":"0","DNSrecords":"0","nameserverId":"0","scanAgent":"0","customer_id":null,"isFolder":"0","isFull":"0","tag":"2","threshold":"0","location":"0","editDate":null,"lastScan":null,"lastDiscovery":null,"calculation":{"Type":"IPv4","IP address":"\/","Network":"172.55.55.0","Broadcast":"172.55.55.7","Subnet bitmask":"29","Subnet netmask":"255.255.255.248","Subnet wildcard":"0.0.0.7","Min host IP":"172.55.55.1","Max host IP":"172.55.55.6","Number of hosts":"6","Subnet Class":false}},"time":0.009}
    #   Response if not exists:
    #     {"code":404,"error":"No subnet 172.66.66.0/29 found in section :group"}
    get '/group/:group/subnet/:address/:prefix' do
      content_type :json 

      begin
        err = validate_required_params(["address", "prefix", "group"], params)
        return err if err.length > 0

        cidr = params[:address] + '/' + params[:prefix]

        phpipam_client = PhpipamClient.new
        return auth_error unless phpipam_client.authenticated?

        phpipam_client.get_subnet_by_section(cidr, params[:group])
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        logger.debug(errors[:no_connection])
        raise 
      end
    end
  end
end
