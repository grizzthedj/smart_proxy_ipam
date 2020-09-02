require 'test_helper'
require 'json'
require 'root/root_v2_api'
require 'smart_proxy_ipam/ipam'

class IpamIntegrationTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::PluginInitializer.new(Proxy::Plugins.instance).initialize_plugins
    Proxy::RootV2Api.new
  end

  def test_features
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('externalipam.yml').returns(enabled: true)
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('externalipam_phpipam.yml').returns({})

    get '/features'

    response = JSON.parse(last_response.body)

    mod = response['externalipam']
    refute_nil(mod)
    assert_equal('running', mod['state'], Proxy::LogBuffer::Buffer.instance.info[:failed_modules][:externalipam])
    assert_equal([], mod['capabilities'])

    expected_settings = {'use_provider' => 'externalipam_phpipam'}
    assert_equal(expected_settings, mod['settings'])
  end
end
