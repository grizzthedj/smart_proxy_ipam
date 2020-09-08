# module ::Proxy::Netbox
#   class Plugin < ::Proxy::Provider
#     plugin :externalipam_netbox, ::Proxy::Ipam::VERSION

#     requires :externalipam, ::Proxy::Ipam::VERSION
#     validate :url, url: true
#     validate_presence :token

#     def load_classes
#       require 'smart_proxy_ipam/netbox/netbox_client.rb'
#     end

#     def load_dependency_injection_wirings(container_instance, settings)
#       container_instance.dependency :externalipam_client, -> { ::Proxy::Netbox::NetboxClient.new(settings) }
#     end
#   end
# end