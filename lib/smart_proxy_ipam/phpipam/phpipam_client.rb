require 'yaml'
require 'json' 
require 'net/http'
require 'monitor'
require 'concurrent'
require 'time'
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
      response = get("subnets/cidr/#{cidr.to_s}")
      json_body = JSON.parse(response.body)

      return response.body if no_subnets_found(json_body)

      json_body['data'] = filter_fields(json_body, [:id, :subnet, :description, :mask])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def get_section(section_name)
      response = get("sections/#{section_name}/")
      response.body
    end

    def get_sections
      response = get('sections/')
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_fields(json_body, [:id, :name, :description])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def get_subnets(section_id)
      response = get("sections/#{section_id}/subnets/")
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_fields(json_body, [:id, :subnet, :mask, :sectionId, :description])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def ip_exists(ip, subnet_id)
      response = get("subnets/#{subnet_id.to_s}/addresses/#{ip}/")
      response.body
    end

    def add_ip_to_subnet(ip, subnet_id, desc)
      data = {:subnetId => subnet_id, :ip => ip, :description => desc}
      response = post('addresses/', data)
      response.body
    end

    def delete_ip_from_subnet(ip, subnet_id)
      response = delete("addresses/#{ip}/#{subnet_id.to_s}/") 
      response.body
    end

    def get_next_ip(subnet_id, mac, cidr)
      response = get("subnets/#{subnet_id.to_s}/first_free/")
      json_body = JSON.parse(response.body)
      subnet_hash = @@ip_cache[cidr.to_sym]

      return {:code => json_body['code'], :error => json_body['message']}.to_json if json_body['message']

      if subnet_hash && subnet_hash.key?(mac.to_sym)
        json_body['data'] = @@ip_cache[cidr.to_sym][mac.to_sym][:ip]
      else
        next_ip = nil
        new_ip = json_body['data']
        ip_not_in_cache = subnet_hash.nil? ? true : !subnet_hash.to_s.include?(new_ip.to_s)

        if ip_not_in_cache
          next_ip = new_ip.to_s
          add_ip_to_cache(new_ip, mac, cidr)
        else
          next_ip = find_new_ip(subnet_id, new_ip, mac, cidr)
        end

        return {:code => 404, :error => "Unable to find another available IP address in subnet #{cidr}"}.to_json if next_ip.nil?
        return {:code => 404, :error => "It is possible that there are no more free addresses in subnet #{cidr}. Available IP's may be cached, and could become available after in-memory IP cache is cleared(up to #{DEFAULT_CLEANUP_INTERVAL} seconds)."}.to_json unless usable_ip(next_ip, cidr)

        json_body['data'] = next_ip
      end

      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
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
    #      "00:0a:95:9d:68:10": {"ip": "100.55.55.1", "timestamp": "2019-09-17 12:03:43 -D400"}
    #   },
    #   "123.11.33.0/24":{  
    #      "00:0a:95:9d:68:33": {"ip": "123.11.33.1", "timestamp": "2019-09-17 12:04:43 -0400"}
    #      "00:0a:95:9d:68:34": {"ip": "123.11.33.2", "timestamp": "2019-09-17 12:05:48 -0400"}
    #      "00:0a:95:9d:68:35": {"ip": "123.11.33.3", "timestamp:: "2019-09-17 12:06:50 -0400"}
    #   }
    # }
    def init_cache
      logger.debug("Clearing ip cache.")
      @@m.synchronize do
        if @@ip_cache and not @@ip_cache.empty?
          @@ip_cache.each do |key, values|
            values.each do |mac, value|
              if Time.now - Time.parse(value[:timestamp]) > DEFAULT_CLEANUP_INTERVAL
                @@ip_cache[key].delete(mac)
              end
            end
            @@ip_cache.delete(key) if @@ip_cache[key].nil? or @@ip_cache[key].empty?
          end
        else
          @@ip_cache = {}
        end
      end
    end

    def add_ip_to_cache(ip, mac, cidr)
      logger.debug("Adding IP #{ip} to cache for subnet #{cidr}")
      @@m.synchronize do
        # Clear cache data which has the same mac and ip with the new one 
        @@ip_cache.each do |key, values|
          if values.keys.include? mac.to_sym
            @@ip_cache[key].delete(mac.to_sym)
          end
          @@ip_cache.delete(key) if @@ip_cache[key].nil? or @@ip_cache[key].empty?
        end   
        
        if @@ip_cache.key?(cidr.to_sym)
          @@ip_cache[cidr.to_sym][mac.to_sym] = {:ip => ip.to_s, :timestamp => Time.now.to_s}
        else
          @@ip_cache = @@ip_cache.merge({cidr.to_sym => {mac.to_sym => {:ip => ip.to_s, :timestamp => Time.now.to_s}}})
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
        if ip_not_found_in_ipam(verify_ip) && !ip_exists_in_cache(new_ip, cidr, mac)
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

    def ip_exists_in_cache(ip, cidr, mac)
      @@ip_cache[cidr.to_sym] && @@ip_cache[cidr.to_sym].to_s.include?(ip.to_s)      
    end

    # Checks if given IP is within a subnet. Broadcast address is considered unusable
    def usable_ip(ip, cidr)
      network = IPAddr.new(cidr)
      network.include?(IPAddr.new(ip)) && network.to_range.last != ip
    end

    def get(path)
      authenticate
      uri = URI(@api_base + path)
      request = Net::HTTP::Get.new(uri)
      request['token'] = @token

      Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }
    end

    def delete(path, body=nil)
      authenticate
      uri = URI(@api_base + path)
      uri.query = URI.encode_www_form(body) if body
      request = Net::HTTP::Delete.new(uri)
      request['token'] = @token

      Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }
    end

    def post(path, body=nil)
      authenticate
      uri = URI(@api_base + path)
      uri.query = URI.encode_www_form(body) if body
      request = Net::HTTP::Post.new(uri)
      request['token'] = @token

      Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }
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
