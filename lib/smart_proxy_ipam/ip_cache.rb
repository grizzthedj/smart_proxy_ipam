require 'yaml'
require 'json'
require 'monitor'
require 'concurrent'
require 'time'
require 'smart_proxy_ipam/ipam_helper'

module Proxy::Ipam
  # Class for managing temp in-memory cache to prevent same IP's being suggested in race conditions
  class IpCache
    include Proxy::Log
    include IpamHelper

    DEFAULT_CLEANUP_INTERVAL = 60
    @@ip_cache = nil
    @@timer_task = nil

    def initialize
      @@m = Monitor.new
      init_cache if @@ip_cache.nil?
      start_cleanup_task if @@timer_task.nil?
    end

    def set_group(group, value)
      @@ip_cache[group.to_sym] = value
    end

    def get_group(group)
      @@ip_cache[group.to_sym]
    end

    def get_cidr(group, cidr)
      @@ip_cache[group.to_sym][cidr.to_sym]
    end

    def get_ip(group_name, cidr, mac)
      @@ip_cache[group_name.to_sym][cidr.to_sym][mac.to_sym][:ip]
    end

    def get_cleanup_interval
      DEFAULT_CLEANUP_INTERVAL
    end

    def ip_exists(ip, cidr, group_name)
      cidr_key = @@ip_cache[group_name.to_sym][cidr.to_sym]&.to_s
      cidr_key.include?(ip.to_s)
    end

    def add(ip, mac, cidr, group_name)
      logger.debug("Adding IP #{ip} to cache for subnet #{cidr} in group #{group_name}")
      @@m.synchronize do
        mac_addr = mac.nil? || mac.empty? ? SecureRandom.uuid : mac
        group_hash = @@ip_cache[group_name.to_sym]

        group_hash.each do |key, values|
          if values.keys.include? mac_addr.to_sym
            @@ip_cache[group_name.to_sym][key].delete(mac_addr.to_sym)
          end
          @@ip_cache[group_name.to_sym].delete(key) if @@ip_cache[group_name.to_sym][key].nil? || @@ip_cache[group_name.to_sym][key].empty?
        end

        if group_hash.key?(cidr.to_sym)
          @@ip_cache[group_name.to_sym][cidr.to_sym][mac_addr.to_sym] = {ip: ip.to_s, timestamp: Time.now.to_s}
        else
          @@ip_cache = @@ip_cache.merge({group_name.to_sym => {cidr.to_sym => {mac_addr.to_sym => {ip: ip.to_s, timestamp: Time.now.to_s}}}})
        end
      end
    end

    private

    def start_cleanup_task
      logger.info('Starting allocated ip address maintenance (used by get_next_ip call).')
      @@timer_task = Concurrent::TimerTask.new(execution_interval: DEFAULT_CLEANUP_INTERVAL) { init_cache }
      @@timer_task.execute
    end

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
          logger.debug('Processing ip cache.')
          @@ip_cache.each do |group, subnets|
            subnets.each do |cidr, macs|
              macs.each do |mac, ip|
                if Time.now - Time.parse(ip[:timestamp]) > DEFAULT_CLEANUP_INTERVAL
                  @@ip_cache[group][cidr].delete(mac)
                end
              end
              @@ip_cache[group].delete(cidr) if @@ip_cache[group][cidr].nil? || @@ip_cache[group][cidr].empty?
            end
          end
        else
          logger.debug('Clearing ip cache.')
          @@ip_cache = {'': {}}
        end
      end
    end
  end
end
