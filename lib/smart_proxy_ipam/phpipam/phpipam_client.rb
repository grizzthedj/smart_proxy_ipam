require 'yaml'
require 'logger'
require 'json' 
require 'net/http'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'

module Proxy::Phpipam
  class PhpipamClient  
    def initialize 
      conf = Proxy::Ipam.get_config[:phpipam]
      @phpipam_config = {url: conf[:url], user: conf[:user], password: conf[:password]}
      @api_base = conf[:url] + '/api/' + conf[:user] + '/'
      @token = nil
    end

    def get_subnet(cidr)
      url = 'subnets/cidr/' + cidr.to_s + '/'
      get(url) 
    end

    def get_next_ip(subnet_id)
      url = 'subnets/' + subnet_id.to_s + '/first_free/'
      get(url)
    end

    def add_ip_to_subnet(ip, subnet_id, desc)
      data = {'subnetId': subnet_id, 'ip': ip, 'description': desc}
      post('addresses/', data) 
    end

    def get_sections
      get('sections/')['data']
    end

    def get_subnets(section_id)
      get('sections/' + section_id.to_s + '/subnets/')
    end

    def ip_exists(ip, subnet_id)
      get('subnets/' + subnet_id.to_s + '/addresses/' + ip + '/')
    end

    def get_subnet_usage(subnet_id)
      get('subnets/' + subnet_id.to_s + '/usage/')
    end

    def delete_ip_from_subnet(ip, subnet_id)
      delete('addresses/' + ip + '/' + subnet_id.to_s + '/') 
    end

    private

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
      request.basic_auth @phpipam_config[:user], @phpipam_config[:password]

      response = Net::HTTP.start(auth_uri.hostname, auth_uri.port) {|http|
        http.request(request)
      }

      response = JSON.parse(response.body)
      @token = response['data']['token']
    end
  end
end