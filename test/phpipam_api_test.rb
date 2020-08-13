require 'test_helper'
require 'rack/test'
require 'test/unit'
require 'smart_proxy_ipam/ipam_api'

ENV['RACK_ENV'] = 'test'

class PhpipamApiTest < ::Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::Ipam::Api.new
  end

  # def test_next_ip_should_return_error_when_parameter_missing
  #   get '/next_ip'
  #   body = JSON.parse(last_response.body)
  #   assert last_response.ok?
  #   assert_not_nil(body['error'])
  # end

  # def test_next_ip_should_not_respond_to_post
  #   post '/next_ip'
  #   assert !last_response.ok?
  # end

  # def test_get_subnet_should_return_error_when_parameter_missing
  #   get '/get_subnet'
  #   body = JSON.parse(last_response.body)
  #   assert last_response.ok?
  #   assert_not_nil(body['error'])
  # end

  # def test_get_subnet_should_not_respond_to_post
  #   post '/get_subnet'
  #   assert !last_response.ok?
  # end

  # def test_get_sections_should_not_respond_to_post
  #   post '/sections'
  #   assert !last_response.ok?
  # end

  # def test_get_subnets_by_section_should_not_respond_to_post
  #   post '/sections/1/subnets'
  #   assert !last_response.ok?
  # end

  # def test_ip_exists_should_return_error_when_parameter_missing
  #   get '/ip_exists'
  #   body = JSON.parse(last_response.body)
  #   assert last_response.ok?
  #   assert_not_nil(body['error'])
  # end

  # def test_ip_exists_should_not_respond_to_post
  #   post '/ip_exists'
  #   assert !last_response.ok?
  # end

  # def test_add_ip_to_subnet_should_return_error_when_parameter_missing
  #   post '/add_ip_to_subnet'
  #   body = JSON.parse(last_response.body)
  #   assert last_response.ok?
  #   assert_not_nil(body['error'])
  # end

  # def test_add_ip_to_subnet_should_not_respond_to_get
  #   get '/add_ip_to_subnet'
  #   assert !last_response.ok?
  # end

  # def test_delete_ip_from_subnet_should_return_error_when_parameter_missing
  #   post '/delete_ip_from_subnet'
  #   body = JSON.parse(last_response.body)
  #   assert last_response.ok?
  #   assert_not_nil(body['error'])
  # end

  # def test_delete_ip_from_subnet_should_not_respond_to_get
  #   get '/delete_ip_from_subnet'
  #   assert !last_response.ok?
  # end
end
