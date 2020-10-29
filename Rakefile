require 'rake'
require 'rake/testtask'

desc 'Default: run unit tests.'
task default: :test

desc 'Test smart_proxy_ipam Plugin'
Rake::TestTask.new(:test) do |t|
  t.libs << '.'
  t.libs << 'lib'
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

desc 'Add files for new IPAM provider'
task :add_provider, [:provider_name] do |args|
  provider_name = args[:provider_name].to_s.downcase
  provider_dir = "lib/smart_proxy_ipam/#{provider_name}"
  provider_example = "settings.d/externalipam_#{provider_name}.yml.example"
  provider_client = "#{provider_dir}/#{provider_name}_client.rb"
  provider_plugin = "#{provider_dir}/#{provider_name}_plugin.rb"
  provider_stubs = %{require 'yaml'
require 'json'
require 'net/http'
require 'uri'
require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_helper'
require 'smart_proxy_ipam/ipam_validator'
require 'smart_proxy_ipam/api_resource'
require 'smart_proxy_ipam/ip_cache'

module Proxy::#{provider_name.capitalize}
  # Implementation class for External IPAM provider phpIPAM
  class #{provider_name.capitalize}Client
    include Proxy::Log
    include Proxy::Ipam::IpamHelper
    include Proxy::Ipam::IpamValidator

    @ip_cache = nil

    def initialize(conf)
      @conf = conf
      @api_base = "<API_BASE_URL>"
      @token = "<API_TOKEN>"
      @api_resource = Proxy::Ipam::ApiResource.new(api_base: @api_base, token: @token)
      @ip_cache = Proxy::Ipam::IpCache.new(provider: '#{provider_name}')
    end

    def get_ipam_subnet(cidr, group_name = nil)
      if group_name.nil?
        get_ipam_subnet_by_cidr(cidr)
      else
        group = get_ipam_group(group_name)
        get_ipam_subnet_by_group(cidr, group[:id])
      end
    end

    def get_ipam_subnet_by_group(cidr, group_id)
      # Should return nil if subnet not found, otherwise a hash with {:id, :subnet, :mask, :description}
    end

    def get_ipam_subnet_by_cidr(cidr)
      # Should return nil if subnet not found, otherwise a hash with {:id, :subnet, :mask, :description}
    end

    def get_ipam_group(group_name)
      # Should raise errors[:no_group] if group is not found, otherwise return a hash with {:id, :name, :description}
    end

    def get_ipam_groups
      # Should return [] if no groups found, otherwise an array of group hashes with {:id, :name, :description}
    end

    def get_ipam_subnets(group_name)
      # Should return nil if group not found or subnets not found, otherwise an array of subnet hashes with {:id, :subnet, :mask, :description}
    end

    def ip_exists?(ip, subnet_id, _group_name)
      # Should return true or false
    end

    def add_ip_to_subnet(ip, params)
      # Should return nil on success, otherwise hash with {:error}
    end

    def delete_ip_from_subnet(ip, params)
      # Should return nil on success, otherwise hash with {:error}
    end

    def get_next_ip(mac, cidr, group_name)
      # Should get next available ip from External IPAM, and should call cache_next_ip
      # to handles the ip caching. Next IP should be returned in the "data" key of a hash

      # ip = @api_resource.get("/provider/path/to/next_ip")
      # next_ip = cache_next_ip(@ip_cache, ip, mac, cidr, subnet_id, group_name)
      # { data: next_ip }
    end

    def groups_supported?
      # Should return true or false, depending on whether groups are supported by the IPAM provider
    end

    def authenticated?
      # Should return true or false, depending on whether the client is authenticated
    end
  end
end
  }
  provider_di = %{module Proxy::#{provider_name.capitalize}
  class Plugin < ::Proxy::Provider
    plugin :externalipam_#{provider_name}, Proxy::Ipam::VERSION

    requires :externalipam, Proxy::Ipam::VERSION
    validate :url, url: true
    validate_presence :token

    load_classes(proc do
      require 'smart_proxy_ipam/#{provider_name}/#{provider_name}_client'
    end)

    load_dependency_injection_wirings(proc do |container_instance, settings|
      container_instance.dependency :externalipam_client, -> { ::Proxy::#{provider_name.capitalize}::#{provider_name.capitalize}Client.new(settings) }
    end)
  end
end
  }
  provider_example_yml = %{---
:url: 'https://#{provider_name}.example.com'
:token: '#{provider_name}_api_token'
  }

  puts "\n==================================================="
  puts "Creating files for new provider #{provider_name}"
  puts "===================================================\n"

  if provider_name.nil? || provider_name.empty?
    raise 'ERROR: A provider name must be specified(bundle exec rake add_provider["providername"])\n\n'
  end

  has_special_chars = !provider_name.index(/[^[:alnum:]]/).nil?
  has_numeric = provider_name.count('0-9').positive?

  if has_special_chars || has_numeric
    raise 'ERROR: Provider name cannot contain numbers or special characters'
  end

  if Dir.exist?(provider_dir)
    raise "ERROR: Directory #{provider_dir} already exists!\n\n"
  end

  Dir.mkdir provider_dir
  puts "Created: #{provider_dir}"

  File.open(provider_client, 'w') { |f| f.write(provider_stubs) }
  puts "Created: #{provider_client}"

  File.open(provider_plugin, 'w') { |f| f.write(provider_di) }
  puts "Created: #{provider_plugin}"

  File.open(provider_example, 'w') { |f| f.write(provider_example_yml) }
  puts "Created: #{provider_example}"

  File.open('lib/smart_proxy_ipam.rb', 'a') do |f|
    f.write("require 'smart_proxy_ipam/#{provider_name}/#{provider_name}_plugin'\n")
  end
  puts 'Updated: lib/smart_proxy_ipam.rb'
end
