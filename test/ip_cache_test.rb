require 'test_helper'
require 'rack/test'
require 'test/unit'
require 'smart_proxy_ipam/ip_cache'

ENV['RACK_ENV'] = 'test'

class IpCacheTest < ::Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::Ipam::Api.new
  end

  def setup
    @ip_cache = Proxy::Ipam::IpCache.instance
    @ip = '172.100.10.1'
    @mac = '00:0a:95:9d:68:10'
    @cidr = '172.100.10.0/29'
    @group_name = 'TestGroup'
  end

  def test_add_ip_to_cache
    @ip_cache.set_group(@group_name, {@cidr.to_sym => {}})
    @ip_cache.add(@ip, @mac, @cidr, @group_name)
    ip = @ip_cache.get_ip(@group_name, @cidr, @mac)
    assert ip == @ip
  end

  def test_ip_exists_to_cache
    @ip_cache.set_group(@group_name, {@cidr.to_sym => {}})
    @ip_cache.add(@ip, @mac, @cidr, @group_name)
    assert @ip_cache.ip_exists(@ip, @cidr, @group_name)
  end

  def test_get_group
    @ip_cache.set_group(@group_name, {@cidr.to_sym => {}})
    group = @ip_cache.get_group(@group_name).to_s
    assert group == '{:"172.100.10.0/29"=>{}}'
  end

  def test_get_cidr
    @ip_cache.set_group(@group_name, {@cidr.to_sym => {'00:0a:95:9d:68:10': {}}})
    cidr = @ip_cache.get_cidr(@group_name, @cidr).to_s
    assert cidr == '{:"00:0a:95:9d:68:10"=>{}}'
  end

  def test_get_ip
    @ip_cache.set_group(@group_name, {@cidr.to_sym => {'00:0a:95:9d:68:10': {'ip': @ip}}})
    ip = @ip_cache.get_ip(@group_name, @cidr, @mac).to_s
    assert ip == @ip
  end
end
