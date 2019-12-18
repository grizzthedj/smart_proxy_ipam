
module Proxy::Ipam
  class NotFound < RuntimeError; end

  class Plugin < ::Proxy::Plugin
    plugin 'externalipam', Proxy::Ipam::VERSION

    http_rackup_path File.expand_path('ipam_http_config.ru', File.expand_path('../', __FILE__))
    https_rackup_path File.expand_path('ipam_http_config.ru', File.expand_path('../', __FILE__))
  end
end
