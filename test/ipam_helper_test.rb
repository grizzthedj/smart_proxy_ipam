require 'test_helper'
require 'rack/test'
require 'test/unit'
require 'smart_proxy_ipam/ipam_helper'

ENV['RACK_ENV'] = 'test'

class IpamHelperTest < ::Test::Unit::TestCase
  include Rack::Test::Methods
  include Proxy::Ipam::IpamHelper

  def app
    Proxy::Ipam::Api.new
  end

  def test_usable_ip_in_cidr
    cidr = '10.20.30.0/29'
    valid_ip = '10.20.30.1'
    assert usable_ip(valid_ip, cidr)
  end

  def test_unusable_ip_in_cidr
    cidr = '10.20.30.0/29'
    invalid_ip = '10.20.30.9'
    refute usable_ip(invalid_ip, cidr)
  end

  def test_increment_ip
    ip = '10.20.30.1'
    incremented_ip = increment_ip(ip)
    assert incremented_ip == '10.20.30.2'
  end
end
