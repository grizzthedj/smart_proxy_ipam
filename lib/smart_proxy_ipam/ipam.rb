module Proxy::Ipam
  class Plugin < ::Proxy::Plugin
    plugin :externalipam, ::Proxy::Ipam::VERSION

    uses_provider
    default_settings use_provider: 'externalipam_phpipam'

    load_classes(proc do
      require 'smart_proxy_ipam/dependency_injection'
      require 'smart_proxy_ipam/ipam_api'
    end)

    http_rackup_path File.expand_path('ipam_http_config.ru', __dir__)
    https_rackup_path File.expand_path('ipam_http_config.ru', __dir__)
  end
end
