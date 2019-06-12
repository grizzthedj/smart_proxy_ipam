require 'test_helper'
require 'rack/test'
require 'test/unit'

require 'smart_proxy_ipam/ipam/ipam_api'

ENV['RACK_ENV'] = 'test'

class IpamApiTest < ::Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::Ipam::Api.new
  end

  def test_phpipam_is_supported_provider
    get '/providers'
    body = JSON.parse(last_response.body)
    assert last_response.ok?
    providers = body['ipam_providers']
    assert_includes(providers, 'phpIPAM')
  end

end
