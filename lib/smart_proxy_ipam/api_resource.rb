require 'yaml'
require 'json'
require 'net/http'
require 'uri'
require 'smart_proxy_ipam/ipam_helper'

class ApiResource
  include ::Proxy::Log
  include IpamHelper

  def initialize(params = {})
    @config = params[:config]
    @api_base = params[:api_base]
    @token = nil
  end

  def get(path)
    uri = URI(@api_base + path)
    request = Net::HTTP::Get.new(uri)
    request['Token'] = @token
    request['Accept'] = 'application/json'
    request['Content-Type'] = 'application/json'

    Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
      http.request(request)
    }
  end

  def delete(path, body=nil)
    uri = URI(@api_base + path)
    uri.query = URI.encode_www_form(body) if body
    request = Net::HTTP::Delete.new(uri)
    request['Token'] = @token
    request['Accept'] = 'application/json'
    request['Content-Type'] = 'application/json'

    Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
      http.request(request)
    }
  end

  def post(path, body=nil)
    uri = URI(@api_base + path)
    uri.query = URI.encode_www_form(body) if body
    request = Net::HTTP::Post.new(uri)
    request['Token'] = @token
    request['Accept'] = 'application/json'
    request['Content-Type'] = 'application/json'

    Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https') {|http|
      http.request(request)
    }
  end

  def authenticate(path)
    auth_uri = URI(@api_base + path)
    request = Net::HTTP::Post.new(auth_uri)
    request.basic_auth @config[:user], @config[:password]

    response = Net::HTTP.start(auth_uri.hostname, auth_uri.port, :use_ssl => auth_uri.scheme == 'https') {|http|
      http.request(request)
    }

    response = JSON.parse(response.body)
    logger.warn(response['message']) if response['message']
    @token = response.dig('data', 'token')
  end

  # def transform_response(response, include_keys)
  #   json_body = JSON.parse(response.body)
  #   json_body = filter_hash(json_body, include_keys)
  #   response.body = json_body.to_json
  #   response.header['Content-Length'] = json_body.to_s.length
  #   response
  # end

  # def transform_json(response, data_keys, include_keys)
  #   json_body = JSON.parse(response.body)
  #   json_body['data'] = filter_fields(json_body, data_keys) if json_body['data']
  #   json_body = filter_hash(json_body, include_keys)
  #   response.body = json_body.to_json
  #   response.header['Content-Length'] = json_body.to_s.length
  #   response.body
  # end 

  def authenticated?
    !@token.nil?
  end
end