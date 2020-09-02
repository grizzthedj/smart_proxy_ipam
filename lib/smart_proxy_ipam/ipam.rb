module Proxy::Ipam
  class Plugin < ::Proxy::Plugin
    plugin 'externalipam', Proxy::Ipam::VERSION

    http_rackup_path File.expand_path('ipam_http_config.ru', __dir__)
    https_rackup_path File.expand_path('ipam_http_config.ru', __dir__)
  end
end
