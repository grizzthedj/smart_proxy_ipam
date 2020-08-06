require 'yaml'
require 'json'
require 'net/http'
require 'monitor'
require 'concurrent'
require 'time'
require 'uri'
require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'
require 'smart_proxy_ipam/netbox/netbox_helper'

module Proxy::Netbox
  class NetboxClient
    include Proxy::Log
    include NetboxHelper

    MAX_RETRIES = 5
    DEFAULT_CLEANUP_INTERVAL = 60 # 2 mins
    @@ip_cache = nil
    @@timer_task = nil

    def initialize
      @conf = Proxy::Ipam.get_config[:netbox]
      @api_base = "#{@conf[:url]}/api/"
      @@m = Monitor.new
      init_cache if @@ip_cache.nil?
      start_cleanup_task if @@timer_task.nil?
    end

    def get_subnet(cidr)
      response = get("ipam/prefixes/?status=active&prefix=#{cidr}")

      json_body = JSON.parse(response.body)

      subnet = {}
      if json_body['count'] == 0
        subnet['error'] = 'No subnets found'
      else
        subnet['data'] = {}
        subnet['data']['subnet'] = json_body['results'][0]['prefix'].split('/').first
        subnet['data']['mask'] = json_body['results'][0]['prefix'].split('/').last
        subnet['data']['description'] = json_body['results'][0]['description']
        subnet['data']['id'] = json_body['results'][0]['id']
      end

      subnet
    end

    def ip_exists?(ip, subnet_id)
      response = get("ipam/ip-addresses/?address=#{ip}")
      json_body = JSON.parse(response.body)

      return false if json_body['count'] == 0
      true
    end

    def add_ip_to_subnet(address, prefix, desc)
      data = { :address => "#{address}/#{prefix}", :nat_outside => 0, :description => desc }.to_json
      response = post('ipam/ip-addresses/', data)

      return nil if response.code.to_s == "201"
      { :error => "Unable to connect to External IPAM server" }
    end

    def delete_ip_from_subnet(ip)
      response = get("ipam/ip-addresses/?address=#{ip}")
      json_body = JSON.parse(response.body)

      return { :error => "No addresses found" } if json_body['count'] == 0

      address_id = json_body['results'][0]['id']
      response = delete("ipam/ip-addresses/#{address_id}/")
      return nil if response.code.to_s == "204"
      { :error => "Unable to delete #{ip} in External IPAM server" }
    end

    def get_next_ip(subnet_id, mac, section_name, cidr)
      response = get("ipam/prefixes/#{subnet_id}/available-ips/?limit=1")
      json_body = JSON.parse(response.body)
      section = section_name.nil? ? "" : section_name
      @@ip_cache[section.to_sym] = {} if @@ip_cache[section.to_sym].nil?
      subnet_hash = @@ip_cache[section.to_sym][cidr.to_sym]

      return { :error => 'No subnets found' } if json_body.empty?

      json_return = {}
      if subnet_hash&.key?(mac.to_sym)
        json_return['data'] = @@ip_cache[section_name.to_sym][cidr.to_sym][mac.to_sym][:ip]
      else
        next_ip = nil
        new_ip = json_body[0]['address'].split('/').first
        ip_not_in_cache = subnet_hash.nil? ? true : !subnet_hash.to_s.include?(new_ip.to_s)

        if ip_not_in_cache
          next_ip = new_ip.to_s
          add_ip_to_cache(new_ip, mac, cidr, section)
        else
          next_ip = find_new_ip(subnet_id, new_ip, mac, cidr, section)
        end

        return { :error => "Unable to find another available IP address in subnet #{cidr}" } if next_ip.nil?
        return { :error => "It is possible that there are no more free addresses in subnet #{cidr}. Available IP's may be cached, and could become available after in-memory IP cache is cleared(up to #{DEFAULT_CLEANUP_INTERVAL} seconds)." } unless usable_ip(next_ip, cidr)

        json_return['data'] = next_ip
      end

      # TODO: Is there a better way to catch this?
      if json_return['error'] && json_return['error'].downcase == "no free addresses found"
        return { :error => json_body['error'] }
      end

      { :data => json_return['data'] }
    end

    def start_cleanup_task
      logger.info("Starting allocated ip address maintenance (used by get_next_ip call).")
      @@timer_task = Concurrent::TimerTask.new(:execution_interval => DEFAULT_CLEANUP_INTERVAL) { init_cache }
      @@timer_task.execute
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
        if @@ip_cache && !@@ip_cache.empty?
          logger.debug("Processing ip cache.")
          @@ip_cache.each do |section, subnets|
            subnets.each do |cidr, macs|
              macs.each do |mac, ip|
                if Time.now - Time.parse(ip[:timestamp]) > DEFAULT_CLEANUP_INTERVAL
                  @@ip_cache[section][cidr].delete(mac)
                end
              end
              @@ip_cache[section].delete(cidr) if @@ip_cache[section][cidr].nil? || @@ip_cache[section][cidr].empty?
            end
          end
        else
          logger.debug("Clearing ip cache.")
          @@ip_cache = { :"" => {} }
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
          if values.keys? mac_addr.to_sym
            @@ip_cache[section_name.to_sym][key].delete(mac_addr.to_sym)
          end
          @@ip_cache[section_name.to_sym].delete(key) if @@ip_cache[section_name.to_sym][key].nil? || @@ip_cache[section_name.to_sym][key].empty?
        end

        if section_hash.key?(cidr.to_sym)
          @@ip_cache[section_name.to_sym][cidr.to_sym][mac_addr.to_sym] = { :ip => ip.to_s, :timestamp => Time.now.to_s }
        else
          @@ip_cache = @@ip_cache.merge({ section_name.to_sym => { cidr.to_sym => { mac_addr.to_sym => { :ip => ip.to_s, :timestamp => Time.now.to_s } } } })
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

        if ip_exists?(new_ip, subnet_id) && !ip_exists_in_cache(new_ip, cidr, mac, section_name)
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
      logger.debug("netbox get " + uri.to_s)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = 'Token ' + @conf[:token]
      request['Accept'] = 'application/json'

      begin
        response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          http.request(request)
        end

        if response.code.to_s != "200"
          logger.warn("Netbox HTTP Error: #{response.code}")
          raise("Netbox HTTP Error: #{response.code}")
        end

        response
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET => e
        logger.warn("Netbox HTTP Error: #{e.message}")
        raise("Netbox HTTP Error: #{e.message}")
      end
    end

    def delete(path)
      uri = URI(@api_base + path)
      logger.debug("netbox delete " + uri.to_s)
      request = Net::HTTP::Delete.new(uri)
      request['Authorization'] = 'Token ' + @conf[:token]
      request['Accept'] = 'application/json'

      begin
        response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          http.request(request)
        end

        if response.code.to_s != "204"
          logger.warn("Netbox HTTP Error: #{response.code}")
          raise("Netbox HTTP Error: #{response.code}")
        end

        response
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET => e
        logger.warn("Netbox HTTP Error: #{e.message}")
        raise("Netbox HTTP Error: #{e.message}")
      end
    end

    def post(path, body)
      logger.debug("netbox post " + path + " " + body.to_s)
      uri = URI(@api_base + path)
      request = Net::HTTP::Post.new(uri)
      request.body = body
      request['Authorization'] = 'Token ' + @conf[:token]
      request['Accept'] = 'application/json'
      request['Content-Type'] = 'application/json'

      begin
        response = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') do |http|
          http.request(request)
        end
        if response.code.to_s != "201"
          logger.warn("Netbox HTTP Error: #{response.code}")
          raise("Netbox HTTP Error: #{response.code}")
        end
        response
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET => e
        logger.warn("Netbox HTTP Error: #{e.message}")
        raise("Netbox HTTP Error: #{e.message}")
      end
    end
  end
end
