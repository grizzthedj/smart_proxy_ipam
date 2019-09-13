require 'yaml'
require 'json' 
require 'net/http'
require 'monitor'
require 'concurrent'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/phpipam/phpipam_helper'

module Proxy::Phpipam
  class PhpipamClient
    include Proxy::Log
    include PhpipamHelper

    MAX_RETRIES = 5
    DEFAULT_CLEANUP_INTERVAL = 120  # 2 mins
    @@ip_cache = nil
    @@timer_task = nil

    def initialize 
      @conf = Proxy::Ipam.get_config[:phpipam]
      @api_base = "#{@conf[:url]}/api/#{@conf[:user]}/"
      @token = nil
      @@m = Monitor.new
      init_cache if @@ip_cache.nil?
      start_cleanup_task if @@timer_task.nil?
    end

    def get_subnet(cidr)
      subnets = get("subnets/cidr/#{cidr.to_s}")
      return {:error => errors[:no_subnet]}.to_json if no_subnets_found(subnets)
      response = []

      # Only return the relevant fields
      subnets['data'].each do |subnet|
        response.push({
          :id => subnet['id'],
          :subnet => subnet['subnet'],
          :description => subnet['description'],
          :mask => subnet['mask']
        })
      end

      response.to_json
    end

    def add_ip_to_subnet(ip, subnet_id, desc)
      data = {:subnetId => subnet_id, :ip => ip, :description => desc}
      post('addresses/', data) 
    end

    def get_section(section_name)
      get("sections/#{section_name}/")["data"]
    end

    def get_sections
      sections = get('sections/')['data']
      response = []

      if sections
        sections.each do |section|
          response.push({
            :id => section['id'],
            :name => section['name'],
            :description => section['description']
          })
        end
      end

      response
    end

    def get_subnets(section_id)
      subnets = get("sections/#{section_id}/subnets/")
      response = [] 

      if subnets && subnets['data']
        # Only return the relevant fields
        subnets['data'].each do |subnet|
          response.push({
            :id => subnet['id'],
            :subnet => subnet['subnet'],
            :mask => subnet['mask'],
            :sectionId => subnet['sectionId'],
            :description => subnet['description']
          })
        end
      end

      response
    end

    def ip_exists(ip, subnet_id)
      usage = get_subnet_usage(subnet_id)

      # We need to check subnet usage first in the case there are zero ips in the subnet. Checking
      # the ip existence on an empty subnet returns a malformed response from phpIPAM(v1.3), containing
      # HTML in the JSON response.
      if usage['data']['used'] == "0"
        return {:ip => ip, :exists => false}.to_json
      else 
        response = get("subnets/#{subnet_id.to_s}/addresses/#{ip}/")

        if ip_not_found_in_ipam(response)
          return {:ip => ip, :exists => false}.to_json
        else 
          return {:ip => ip, :exists => true}.to_json
        end
      end
    end

    
    def get_subnet_usage(subnet_id)
      get("subnets/#{subnet_id.to_s}/usage/")
    end

    def delete_ip_from_subnet(ip, subnet_id)
      delete("addresses/#{ip}/#{subnet_id.to_s}/") 
    end

    def get_next_ip(subnet_id, mac, cidr)
      response = get("subnets/#{subnet_id.to_s}/first_free/")
      subnet_hash = @@ip_cache[cidr.to_sym]

      return response if response['message']

      if subnet_hash && subnet_hash.key?(mac.to_sym)
        response['next_ip'] = @@ip_cache[cidr.to_sym][mac.to_sym]
      else
        new_ip = response['data']
        ip_not_in_cache = subnet_hash && subnet_hash.key(new_ip).nil?

        if ip_not_in_cache
          next_ip = new_ip.to_s
          add_ip_to_cache(new_ip, mac, cidr)
        else
          next_ip = find_new_ip(subnet_id, new_ip, mac, cidr)
        end

        if next_ip.nil?
          response['error'] = "Unable to find another available IP address in subnet #{cidr}"
          return response
        end

        unless usable_ip(next_ip, cidr)
          response['error'] = "It is possible that there are no more free addresses in subnet #{cidr}. Available IP's may be cached, and could become available after in-memory IP cache is cleared(up to #{CLEAR_CACHE_DELAY} seconds)."
          return response
        end

        response['next_ip'] = next_ip
      end

      response
    end

    def start_cleanup_task
      logger.info("Starting allocated ip address maintenance (used by get_next_ip call).")
      @@timer_task = Concurrent::TimerTask.new(:execution_interval => DEFAULT_CLEANUP_INTERVAL) { init_cache }
      @@timer_task.execute
    end

    private

    # @@ip_cache structure
    # {  
    #   "100.55.55.0/24":{  
    #      "00:0a:95:9d:68:10": "100.55.55.1"
    #   },
    #   "123.11.33.0/24":{  
    #     "00:0a:95:9d:68:33": "123.11.33.1",
    #     "00:0a:95:9d:68:34": "123.11.33.2",
    #     "00:0a:95:9d:68:35": "123.11.33.3"
    #   }
    # }
    def init_cache
      logger.debug("Clearing ip cache.")
      @@m.synchronize do
        @@ip_cache = {}
      end
    end

    def add_ip_to_cache(ip, mac, cidr)
      logger.debug("Adding IP #{ip} to cache for subnet #{cidr}")
      @@m.synchronize do
        if @@ip_cache.key?(cidr.to_sym)
          @@ip_cache[cidr.to_sym][mac.to_sym] = ip.to_s
        else
          @@ip_cache = @@ip_cache.merge({cidr.to_sym => {mac.to_sym => ip.to_s}})
        end
      end
    end

    # Called when next available IP from external IPAM has been cached by another user/host, but 
    # not actually persisted in external IPAM. Will increment the IP(MAX_RETRIES times), and 
    # see if it is available in external IPAM.
    def find_new_ip(subnet_id, ip, mac, cidr)
      found_ip = nil
      temp_ip = ip
      retry_count = 0

      loop do
        new_ip = increment_ip(temp_ip)
        verify_ip = JSON.parse(ip_exists(new_ip, subnet_id))

        # If new IP doesn't exist in IPAM and not in the cache
        if verify_ip['exists'] == false && !ip_exists_in_cache(new_ip, cidr)
          found_ip = new_ip.to_s
          add_ip_to_cache(found_ip, mac, cidr)
          break
        end

        temp_ip = new_ip
        retry_count += 1
        break if retry_count >= MAX_RETRIES
      end

      # Return the original IP found in external ipam if no new ones found after MAX_RETRIES
      return ip if found_ip.nil?

      found_ip
    end

    def increment_ip(ip)
      IPAddr.new(ip.to_s).succ.to_s
    end

    def ip_exists_in_cache(ip, cidr)
      @@ip_cache[cidr.to_sym] && !@@ip_cache[cidr.to_sym].key(ip).nil?
    end

    # Checks if given IP is within a subnet. Broadcast address is considered unusable
    def usable_ip(ip, cidr)
      network = IPAddr.new(cidr)
      network.include?(IPAddr.new(ip)) && network.to_range.last != ip
    end

    def get(path, body=nil)
      authenticate
      uri = URI(@api_base + path)
      uri.query = URI.encode_www_form(body) if body
      request = Net::HTTP::Get.new(uri)
      request['token'] = @token

      response = Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }

      JSON.parse(response.body)
    end

    def delete(path, body=nil)
      authenticate
      uri = URI(@api_base + path)
      uri.query = URI.encode_www_form(body) if body
      request = Net::HTTP::Delete.new(uri)
      request['token'] = @token

      response = Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }

      JSON.parse(response.body)
    end

    def post(path, body=nil)
      authenticate
      uri = URI(@api_base + path)
      uri.query = URI.encode_www_form(body) if body
      request = Net::HTTP::Post.new(uri)
      request['token'] = @token

      response = Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }

      JSON.parse(response.body)
    end

    def authenticate
      auth_uri = URI(@api_base + '/user/')
      request = Net::HTTP::Post.new(auth_uri)
      request.basic_auth @conf[:user], @conf[:password]

      response = Net::HTTP.start(auth_uri.hostname, auth_uri.port) {|http|
        http.request(request)
      }

      response = JSON.parse(response.body)
      @token = response['data']['token']
    end    
  end
end