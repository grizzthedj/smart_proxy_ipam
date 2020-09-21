require 'test_helper'
require 'rack/test'
require 'test/unit'
require 'json'
require 'root/root_v2_api'
require 'smart_proxy_ipam/ipam'

ENV['RACK_ENV'] = 'test'

class IpamIntegrationTest < ::Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Proxy::PluginInitializer.new(Proxy::Plugins.instance).initialize_plugins
    Proxy::RootV2Api.new
  end

  def test_features
    plugin_settings = {
      enabled: true,
    }
    provider_settings = {
      url: 'https://phpipam.example.com',
      user: 'myuser',
      password: 'mypassword',
    }

    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('externalipam.yml').returns(plugin_settings)
    Proxy::DefaultModuleLoader.any_instance.expects(:load_configuration_file).with('externalipam_phpipam.yml').returns(provider_settings)

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