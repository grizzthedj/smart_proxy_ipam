require 'test_helper'
require 'rack/test'
require 'test/unit'
require 'smart_proxy_ipam/ipam_helper'

ENV['RACK_ENV'] = 'test'

class IpamHelperTest < ::Test::Unit::TestCase
  include Rack::Test::Methods
  include IpamHelper

  def app
    Proxy::Ipam::Api.new
  end

  def test_validate_mac_should_return_valid_mac_address
    good_mac = '3c:51:0e:df:9f:01'
    validated_mac = validate_mac!(good_mac)
    assert validated_mac == good_mac
  end

  def test_validate_mac_should_return_nil_for_invalid_mac_address
    bad_mac = 'this is not a mac address'
    validated_mac = validate_mac!(bad_mac)
    assert validated_mac.nil?
  end

  def test_validate_ip_should_return_valid_ip_address
    good_ip = '172.10.40.33'
    validated_ip = validate_ip!(good_ip)
    assert validated_ip == good_ip
  end

  def test_validate_ip_should_return_nil_for_invalid_ip_address
    bad_ip = 'this is not an ip address'
    validated_ip = validate_ip!(bad_ip)
    assert validated_ip.nil?
  end

  def test_validate_cidr_should_return_valid_cidr
    address = '172.10.40.0'
    prefix = '29'
    validated_cidr = validate_cidr!(address, prefix)
    assert validated_cidr == address + '/' + prefix
  end

  def test_validate_cidr_should_return_nil_for_invalid_cidr
    address = 'bad address'
    prefix = 'bad prefix'
    validated_cidr = validate_cidr!(address, prefix)
    assert validated_cidr.nil?
  end
end
