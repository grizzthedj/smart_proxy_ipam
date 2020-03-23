require 'yaml'
require 'json'
require 'net/http'
require 'monitor'
require 'concurrent'
require 'time'
require 'uri'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/phpipam/phpipam_helper'

module Proxy::Phpipam
  class PhpipamClient
    include Proxy::Log
    include PhpipamHelper

    MAX_RETRIES = 5
    DEFAULT_CLEANUP_INTERVAL = 60  # 2 mins
    @@ip_cache = nil
    @@timer_task = nil

    def initialize
      @conf = Proxy::Ipam.get_config[:phpipam]
      @api_base = "#{@conf[:url]}/api/#{@conf[:user]}/"
      @token = nil
      @@m = Monitor.new
      init_cache if @@ip_cache.nil?
      start_cleanup_task if @@timer_task.nil?
      authenticate
    end

    def get_subnet(cidr, section_name = nil)
      if section_name.nil? || section_name.empty?
        get_subnet_by_cidr(cidr)
      else
        get_subnet_by_section(cidr, section_name)
      end
    end

    def get_subnet_by_section(cidr, section_name, include_id = true)
      section = JSON.parse(get_section(section_name))

      return {:error => "No section #{URI.unescape(section_name)} found"}.to_json if no_section_found?(section)

      subnets = JSON.parse(get_subnets(section['data']['id'], include_id))
      subnet_id = nil

      subnets['data'].each do |subnet|
        subnet_cidr = subnet['subnet'] + '/' + subnet['mask']
        subnet_id = subnet['id'] if subnet_cidr == cidr
      end

      return {}.to_json if subnet_id.nil?

      response = get("subnets/#{subnet_id.to_s}/")
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_hash(json_body['data'], [:id, :subnet, :mask, :description]) if json_body['data']
      json_body = filter_hash(json_body, [:data, :error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def get_subnet_by_cidr(cidr)
      response = get("subnets/cidr/#{cidr.to_s}")
      json_body = JSON.parse(response.body)
      return {}.to_json if json_body['data'].nil?
      json_body['data'] = filter_fields(json_body, [:id, :subnet, :description, :mask])[0]
      json_body = filter_hash(json_body, [:data, :error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def get_section(section_name)
      response = get("sections/#{section_name}/")
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_hash(json_body['data'], [:id, :name, :description]) if json_body['data']
      json_body = filter_hash(json_body, [:data, :error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def get_sections
      response = get('sections/')
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_fields(json_body, [:id, :name, :description]) if json_body['data']
      json_body = filter_hash(json_body, [:data, :error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def get_subnets(section_id, include_id = true)
      response = get("sections/#{section_id}/subnets/")
      fields = [:subnet, :mask, :description]
      fields.push(:id) if include_id
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_fields(json_body, fields) if json_body['data']
      json_body = filter_hash(json_body, [:data, :error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def ip_exists(ip, subnet_id)
      response = get("subnets/#{subnet_id.to_s}/addresses/#{ip}/")
      json_body = JSON.parse(response.body)
      json_body['data'] = filter_fields(json_body, [:ip]) if json_body['data']
      json_body = filter_hash(json_body, [:data, :error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response
    end

    def add_ip_to_subnet(ip, subnet_id, desc)
      data = {:subnetId => subnet_id, :ip => ip, :description => desc}
      response = post('addresses/', data)
      json_body = JSON.parse(response.body)
      json_body = filter_hash(json_body, [:error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response
    end

    def delete_ip_from_subnet(ip, subnet_id)
      response = delete("addresses/#{ip}/#{subnet_id.to_s}/")
      json_body = JSON.parse(response.body)
      json_body = filter_hash(json_body, [:error, :message])
      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response
    end

    def get_next_ip(subnet_id, mac, cidr, section_name)
      response = get("subnets/#{subnet_id.to_s}/first_free/")
      json_body = JSON.parse(response.body)
      section = section_name.nil? ? "" : section_name
      @@ip_cache[section.to_sym] = {} if @@ip_cache[section.to_sym].nil?
      subnet_hash = @@ip_cache[section.to_sym][cidr.to_sym]

      return {:error => json_body['message']}.to_json if json_body['message']

      if subnet_hash && subnet_hash.key?(mac.to_sym)
        json_body['data'] = @@ip_cache[section_name.to_sym][cidr.to_sym][mac.to_sym][:ip]
      else
        next_ip = nil
        new_ip = json_body['data']
        ip_not_in_cache = subnet_hash.nil? ? true : !subnet_hash.to_s.include?(new_ip.to_s)

        if ip_not_in_cache
          next_ip = new_ip.to_s
          add_ip_to_cache(new_ip, mac, cidr, section)
        else
          next_ip = find_new_ip(subnet_id, new_ip, mac, cidr, section)
        end

        return {:error => "Unable to find another available IP address in subnet #{cidr}"}.to_json if next_ip.nil?
        return {:error => "It is possible that there are no more free addresses in subnet #{cidr}. Available IP's may be cached, and could become available after in-memory IP cache is cleared(up to #{DEFAULT_CLEANUP_INTERVAL} seconds)."}.to_json unless usable_ip(next_ip, cidr)

        json_body['data'] = next_ip
      end

      json_body = {:data => json_body['data']}

      response.body = json_body.to_json
      response.header['Content-Length'] = json_body.to_s.length
      response.body
    end

    def start_cleanup_task
      logger.info("Starting allocated ip address maintenance (used by get_next_ip call).")
      @@timer_task = Concurrent::TimerTask.new(:execution_interval => DEFAULT_CLEANUP_INTERVAL) { init_cache }
      @@timer_task.execute
    end

    def authenticated?
      !@token.nil?
    end

    private

    # @@ip_cache structure
    #
    # Groups of subnets are cached under the External IPAM Group name. For example,
    # "IPAM Group Name" would be the section name in phpIPAM. All IP's cached for subnets
    # that do not have an External IPAM group specified, they are cached under the "" key. IP's
    # are cached using one of two possible keys:
    #    1). Mac Address
    #    2). UUID (Used when Mac Address not specified)
    #
    # {
    #   "": {
    #     "100.55.55.0/24":{
    #       "00:0a:95:9d:68:10": {"ip": "100.55.55.1", "timestamp": "2019-09-17 12:03:43 -D400"},
    #       "906d8bdc-dcc0-4b59-92cb-665935e21662": {"ip": "100.55.55.2", "timestamp": "2019-09-17 11:43:22 -D400"}
    #     },
    #   },
    #   "IPAM Group Name": {
    #     "123.11.33.0/24":{
    #       "00:0a:95:9d:68:33": {"ip": "123.11.33.1", "timestamp": "2019-09-17 12:04:43 -0400"},
    #       "00:0a:95:9d:68:34": {"ip": "123.11.33.2", "timestamp": "2019-09-17 12:05:48 -0400"},
    #       "00:0a:95:9d:68:35": {"ip": "123.11.33.3", "timestamp:: "2019-09-17 12:06:50 -0400"}
    #     }
    #   },
    #   "Another IPAM Group": {
    #     "185.45.39.0/24":{
    #       "00:0a:95:9d:68:55": {"ip": "185.45.39.1", "timestamp": "2019-09-17 12:04:43 -0400"},
    #       "00:0a:95:9d:68:56": {"ip": "185.45.39.2", "timestamp": "2019-09-17 12:05:48 -0400"}
    #     }
    #   }
    # }
    def init_cache
      @@m.synchronize do
        if @@ip_cache and not @@ip_cache.empty?
          logger.debug("Processing ip cache.")
          @@ip_cache.each do |section, subnets|
            subnets.each do |cidr, macs|
              macs.each do |mac, ip|
                if Time.now - Time.parse(ip[:timestamp]) > DEFAULT_CLEANUP_INTERVAL
                  @@ip_cache[section][cidr].delete(mac)
                end
              end
              @@ip_cache[section].delete(cidr) if @@ip_cache[section][cidr].nil? or @@ip_cache[section][cidr].empty?
            end
          end
        else
          logger.debug("Clearing ip cache.")
          @@ip_cache = {:"" => {}}
        end
      end
    end

    def add_ip_to_cache(ip, mac, cidr, section_name)
      logger.debug("Adding IP #{ip} to cache for subnet #{cidr} in section #{section_name}")
      @@m.synchronize do
        # Clear cache data which has the same mac and ip with the new one

        mac_addr = (mac.nil? || mac.empty?) ? SecureRandom.uuid : mac
        section_hash = @@ip_cache[section_name.to_sym]

        section_hash.each do |key, values|
          if values.keys.include? mac_addr.to_sym
            @@ip_cache[section_name.to_sym][key].delete(mac_addr.to_sym)
          end
          @@ip_cache[section_name.to_sym].delete(key) if @@ip_cache[section_name.to_sym][key].nil? or @@ip_cache[section_name.to_sym][key].empty?
        end

        if section_hash.key?(cidr.to_sym)
          @@ip_cache[section_name.to_sym][cidr.to_sym][mac_addr.to_sym] = {:ip => ip.to_s, :timestamp => Time.now.to_s}
        else
          @@ip_cache = @@ip_cache.merge({section_name.to_sym => {cidr.to_sym => {mac_addr.to_sym => {:ip => ip.to_s, :timestamp => Time.now.to_s}}}})
        end
      end
    end

    # Called when next available IP from external IPAM has been cached by another user/host, but
    # not actually persisted in external IPAM. Will increment the IP(MAX_RETRIES times), and
    # see if it is available in external IPAM.
    def find_new_ip(subnet_id, ip, mac, cidr, section_name)
      found_ip = nil
      temp_ip = ip
      retry_count = 0

      loop do
        new_ip = increment_ip(temp_ip)
        verify_ip = JSON.parse(ip_exists(new_ip, subnet_id).body)

        # If new IP doesn't exist in IPAM and not in the cache
        if ip_not_found_in_ipam?(verify_ip) && !ip_exists_in_cache(new_ip, cidr, mac, section_name)
          found_ip = new_ip.to_s
          add_ip_to_cache(found_ip, mac, cidr, section_name)
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

    def ip_exists_in_cache(ip, cidr, mac, section_name)
      @@ip_cache[section_name.to_sym][cidr.to_sym] && @@ip_cache[section_name.to_sym][cidr.to_sym].to_s.include?(ip.to_s)
    end

    # Checks if given IP is within a subnet. Broadcast address is considered unusable
    def usable_ip(ip, cidr)
      network = IPAddr.new(cidr)
      network.include?(IPAddr.new(ip)) && network.to_range.last != ip
    end

    def get(path)
      uri = URI(@api_base + path)
      request = Net::HTTP::Get.new(uri)
      request['token'] = @token

      Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }
    end

    def delete(path, body=nil)
      uri = URI(@api_base + path)
      uri.query = URI.encode_www_form(body) if body
      request = Net::HTTP::Delete.new(uri)
      request['token'] = @token

      Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(request)
      }
    end

    def post(path, body=nil)
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
      logger.warn(response['message']) if response['message']
      @token = response.dig('data', 'token')
    end
  end
end
