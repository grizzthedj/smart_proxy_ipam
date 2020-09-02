module ::Proxy::Phpipam
  class Plugin < ::Proxy::Provider
    plugin :externalipam_phpipam, ::Proxy::Ipam::VERSION

    requires :externalipam, ::Proxy::Ipam::VERSION
    validate :url, url: true
    validate_presence :user, :password

    def load_classes
      require 'smart_proxy_ipam/phpipam/phpipam_client.rb'
    end

    def load_dependency_injection_wirings(container_instance, settings)
      container_instance.dependency :externalipam_client, -> { ::Proxy::Phpipam::PhpipamClient.new(settings) }
    end
  end
end
