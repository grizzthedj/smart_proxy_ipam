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
    # Input:   cidr(string): CIDR address in the format: "100.20.20.0/24"
    # Returns: Hash with "next_ip", or hash with "error"
    # Examples: 
    #   Response if success: 
    #     {"cidr":"100.20.20.0/24","next_ip":"100.20.20.11"}
    #   Response if :error =>   
    #     {"error":"The specified subnet does not exist in phpIPAM."}
    get '/next_ip' do
      content_type :json

      begin
        err = validate_required_params(["cidr", "mac"], params)
        return err if err.length > 0

        cidr = params[:cidr]
        mac = params[:mac]
        phpipam_client = PhpipamClient.new
        subnet = JSON.parse(phpipam_client.get_subnet(cidr))

        return {:error => errors[:no_subnet]}.to_json if no_subnets_found(subnet)

        ipaddr = phpipam_client.get_next_ip(subnet['data'][0]['id'], mac, cidr)

        return {:error => errors[:no_free_ip]}.to_json if no_free_ip_found(JSON.parse(ipaddr))

        ipaddr
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
      end
    end

    # Gets the subnet from phpIPAM
    # 
    # Input:   cidr(string): CIDR address in the format: "100.20.20.0/24"
    # Returns: JSON with "data" key on success, or JSON with "error" key when there is an error
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
    get '/get_subnet' do
      content_type :json

      begin
        err = validate_required_params(["cidr"], params)
        return err if err.length > 0

        phpipam_client = PhpipamClient.new
        phpipam_client.get_subnet(params[:cidr])
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
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
    get '/sections' do
      content_type :json

      begin
        phpipam_client = PhpipamClient.new
        phpipam_client.get_sections
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
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
    get '/sections/:section_name/subnets' do
      content_type :json 

      begin
        err = validate_required_params(["section_name"], params)
        return err if err.length > 0
 
        section_name = URI.decode(params[:section_name])
        phpipam_client = PhpipamClient.new
        section = JSON.parse(phpipam_client.get_section(section_name))

        return {:error => errors[:no_section]}.to_json if no_section_found(section)

        phpipam_client.get_subnets(section['data']['id'].to_s)
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
      end
    end

    # Checks whether an IP address has already been taken in external ipam.
    #
    # Inputs: 1. ip(string). IP address to be checked.
    #         2. cidr(string): CIDR address in the format: "100.20.20.0/24"
    # Returns: JSON object with 'exists' field being either true or false
    # Example: 
    #   Response if exists: 
    #     {"ip":"100.20.20.18","exists":true}
    #   Response if not exists:
    #     {"ip":"100.20.20.18","exists":false}
    get '/ip_exists' do
      content_type :json 

      begin
        err = validate_required_params(["cidr", "ip"], params)
        return err if err.length > 0

        phpipam_client = PhpipamClient.new
        subnet = JSON.parse(phpipam_client.get_subnet(params[:cidr]))

        return {:error => errors[:no_subnet]}.to_json if no_subnets_found(subnet)

        phpipam_client.ip_exists(params[:ip], subnet['data'][0]['id'])
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
      end
    end

    # Adds an IP address to the specified subnet 
    #
    # Inputs: 1. ip(string):    IP address to be added.
    #         2. cidr(string):  The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24", IPv6 - "2001:db8:abcd:12::/124")
    # 
    # Returns: Hash with "message" on success, or hash with "error" 
    # 
    # Examples:
    #   Response if success: 
    #     IPv4: {"message":"IP 100.10.10.123 added to subnet 100.10.10.0/24 successfully."}
    #     IPv6: {"message":"IP 2001:db8:abcd:12::3 added to subnet 2001:db8:abcd:12::/124 successfully."}
    #   Response if :error =>   
    #     {"error":"The specified subnet does not exist in phpIPAM."}
    post '/add_ip_to_subnet' do
      content_type :json

      begin
        err = validate_required_params(["cidr", "ip"], params)
        return err if err.length > 0

        ip = params[:ip]
        cidr = params[:cidr]
        phpipam_client = PhpipamClient.new
        subnet = JSON.parse(phpipam_client.get_subnet(cidr))

        return {:error => errors[:no_subnet]}.to_json if no_subnets_found(subnet)

        phpipam_client.add_ip_to_subnet(ip, subnet['data'][0]['id'], 'Address auto added by Foreman')
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
      end
    end

    # Deletes IP address from a given subnet
    #
    # Inputs: 1. ip(string).   IP address to be checked.
    #         2. cidr(string): The IPv4 or IPv6 subnet CIDR. (Examples: IPv4 - "100.10.10.0/24", IPv6 - "2001:db8:abcd:12::/124")
    #
    # Returns: JSON object
    # Example:
    #   Response if success: 
    #     {"code": 200, "success": true, "message": "Address deleted", "time": 0.017}
    #   Response if :error =>   
    #     {"code": 404, "success": 0, "message": "Address does not exist", "time": 0.008}
    post '/delete_ip_from_subnet' do
      content_type :json

      begin
        err = validate_required_params(["cidr", "ip"], params)
        return err if err.length > 0

        ip = params[:ip]
        cidr = params[:cidr]
        phpipam_client = PhpipamClient.new
        subnet = JSON.parse(phpipam_client.get_subnet(cidr))

        return {:error => errors[:no_subnet]}.to_json if no_subnets_found(subnet)

        phpipam_client.delete_ip_from_subnet(ip, subnet['data'][0]['id'])
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET
        return {:error => errors[:no_connection]}.to_json
      end
    end
  end
end
