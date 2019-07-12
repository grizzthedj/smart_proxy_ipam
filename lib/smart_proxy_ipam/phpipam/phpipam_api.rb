require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/phpipam/phpipam_client'

# TODO: Refactor later to handle multiple IPAM providers. For now, it is 
# just phpIPAM that is supported
module Proxy::Phpipam
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    get '/providers' do
      content_type :json
      {:ipam_providers => ['phpIPAM']}.to_json
    end

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
        cidr = params[:cidr]

        if not cidr
          return {:error => "A 'cidr' parameter for the subnet must be provided(e.g. 100.10.10.0/24)"}.to_json
        end

        phpipam_client = PhpipamClient.new
        response = phpipam_client.get_subnet(cidr)

        if response['message'] && response['message'].downcase == "no subnets found"
          return {:error => "The specified subnet does not exist in External IPAM."}.to_json
        end
  
        subnet_id = JSON.parse(response)[0]['id']
        response = phpipam_client.get_next_ip(subnet_id)

        if response['message'] && response['message'].downcase == "no free addresses found"
          return {:error => "There are no more free addresses in subnet #{cidr}"}.to_json
        end

        {:cidr => cidr, :next_ip => response['data']}.to_json
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
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
        cidr = params[:cidr]

        if not cidr
          return {:error => "A 'cidr' parameter for the subnet must be provided(e.g. 100.10.10.0/24)"}.to_json
        end

        phpipam_client = PhpipamClient.new
        subnet = phpipam_client.get_subnet(cidr)
        subnet.to_json
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
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
        sections = phpipam_client.get_sections
        sections.to_json
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
      end
    end

    # Get a list of subnets for given external ipam section
    #
    # Input: section_id(integer). The id of the external ipam section
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
    #     {"error":"Unable to connect to phpIPAM server"}
    get '/sections/:section_id/subnets' do
      content_type :json 

      begin
        section_id = params[:section_id]
        
        if not section_id
          return {:error => "A 'section_id' must be provided"}.to_json
        end

        phpipam_client = PhpipamClient.new
        subnets = phpipam_client.get_subnets(section_id)
        subnets.to_json
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
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
        cidr = params[:cidr]
        ip = params[:ip]

        return {:error => "Missing 'cidr' parameter. A CIDR IPv4 address must be provided(e.g. 100.10.10.0/24)"}.to_json if not cidr
        return {:error => "Missing 'ip' parameter. An IPv4 address must be provided(e.g. 100.10.10.22)"}.to_json if not ip

        phpipam_client = PhpipamClient.new
        subnet = phpipam_client.get_subnet(cidr)

        if subnet['message'] && subnet['message'].downcase == "no subnets found"
          return {:error => "The specified subnet does not exist in External IPAM."}.to_json
        end

        subnet_id = JSON.parse(subnet)[0]['id']
        phpipam_client.ip_exists(ip, subnet_id)
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
      end
    end

    # Adds an IP address to the specified subnet 
    #
    # Inputs: 1. ip(string). IP address to be added.
    #         2. subnet_id(integer). The id of the external ipam subnet
    #         3. description(string). IP address description
    # Returns: Hash with "message" on success, or hash with "error" 
    # Examples:
    #   Response if success: 
    #     {"message":"IP 100.10.10.123 added to subnet 100.10.10.0/24 successfully."}
    #   Response if :error =>   
    #     {"error":"The specified subnet does not exist in phpIPAM."}
    post '/add_ip_to_subnet' do
      content_type :json

      begin
        cidr = params[:cidr]
        ip = params[:ip]

        return {:error => "Missing 'cidr' parameter. A CIDR IPv4 address must be provided(e.g. 100.10.10.0/24)"}.to_json if not cidr
        return {:error => "Missing 'ip' parameter. An IPv4 address must be provided(e.g. 100.10.10.22)"}.to_json if not ip

        phpipam_client = PhpipamClient.new
        response = phpipam_client.get_subnet(cidr)

        if response['message'] && response['message'].downcase == "no subnets found"
          return {:error => "The specified subnet does not exist in External IPAM."}.to_json
        end

        subnet_id = JSON.parse(response)[0]['id']

        phpipam_client.add_ip_to_subnet(ip, subnet_id, 'Address auto added by Foreman')

        {:message => "IP #{ip} added to subnet #{cidr} successfully."}.to_json
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
      end
    end

    # Deletes IP address from a given subnet
    #
    # Inputs: 1. ip(string). IP address to be checked.
    #         2. cidr(string): CIDR address in the format: "100.20.20.0/24"
    # Returns: JSON object
    # Example:
    #   Response if success: 
    #     {"code": 200, "success": true, "message": "Address deleted", "time": 0.017}
    #   Response if :error =>   
    #     {"code": 404, "success": 0, "message": "Address does not exist", "time": 0.008}
    post '/delete_ip_from_subnet' do
      content_type :json

      begin
        cidr = params[:cidr]
        ip = params[:ip]

        return {:error => "Missing 'cidr' parameter. A CIDR IPv4 address must be provided(e.g. 100.10.10.0/24)"}.to_json if not cidr
        return {:error => "Missing 'ip' parameter. An IPv4 address must be provided(e.g. 100.10.10.22)"}.to_json if not ip

        phpipam_client = PhpipamClient.new
        response = phpipam_client.get_subnet(cidr)

        if response['message'] && response['message'].downcase == "no subnets found"
          return {:error => "The specified subnet does not exist in External IPAM."}.to_json
        end

        subnet_id = JSON.parse(response)[0]['id']

        phpipam_client.delete_ip_from_subnet(ip, subnet_id)

        {:message => "IP #{ip} deleted from subnet #{cidr} successfully."}.to_json
      rescue Errno::ECONNREFUSED
        return {:error => "Unable to connect to External IPAM server"}.to_json
      end
    end

  end
end
