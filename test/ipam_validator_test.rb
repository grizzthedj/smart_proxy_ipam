require 'test_helper'
require 'rack/test'
require 'test/unit'
require 'smart_proxy_ipam/ipam_validator'

ENV['RACK_ENV'] = 'test'

class IpamValidatorTest < ::Test::Unit::TestCase
  include Rack::Test::Methods
  include Proxy::Ipam::IpamValidator

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
    assert_raise Proxy::Validations::Error do
      validate_mac!(bad_mac)
    end
  end

  def test_validate_ip_should_return_valid_ipv4_address
    good_ip = '172.10.40.33'
    validated_ip = validate_ip!(good_ip)
    assert validated_ip == good_ip
  end

  def test_validate_ip_should_raise_exception_for_invalid_ipv4_address
    bad_ip = 'this is not an ip address'
    assert_raise Proxy::Validations::Error do
      validate_ip!(bad_ip)
    end
    bad_ip = '172.10.40.555'
    assert_raise Proxy::Validations::Error do
      validate_ip!(bad_ip)
    end
  end

  def test_validate_ip_should_return_valid_ipv6_address
    good_ip = 'ff02::1'
    validated_ip = validate_ip!(good_ip)
    assert validated_ip == good_ip
  end

  def test_validate_ip_should_raise_exception_for_invalid_ipv6_address
    bad_ip = 'ff02::1::1'
    assert_raise Proxy::Validations::Error do
      validate_ip!(bad_ip)
    end
    bad_ip = 'this is not an ip address'
    assert_raise Proxy::Validations::Error do
      validate_ip!(bad_ip)
    end
  end

  def test_validate_cidr_should_return_valid_cidr
    address = '172.10.40.0'
    prefix = '29'
    validated_cidr = validate_cidr!(address, prefix)
    assert validated_cidr == "#{address}/#{prefix}"
  end

  def test_validate_cidr_should_return_nil_for_invalid_cidr
    address = 'bad address'
    prefix = 'bad prefix'
    assert_raise Proxy::Validations::Error do
      validate_cidr!(address, prefix)
    end
  end
end
