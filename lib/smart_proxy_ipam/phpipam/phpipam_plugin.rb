module Proxy::Phpipam
  class Plugin < ::Proxy::Provider
    plugin :externalipam_phpipam, Proxy::Ipam::VERSION

    requires :externalipam, Proxy::Ipam::VERSION
    validate :url, url: true
    validate_presence :user, :password

    load_classes(proc do
      require 'smart_proxy_ipam/phpipam/phpipam_client'
    end)

    load_dependency_injection_wirings(proc do |container_instance, settings|
      container_instance.dependency :externalipam_client, -> { ::Proxy::Phpipam::PhpipamClient.new(settings) }
    end)
  end
end
