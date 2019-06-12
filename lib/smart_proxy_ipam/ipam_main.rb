
module Proxy::Ipam
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self
    def get_config
      Proxy::Ipam::Plugin.settings.external_ipam
    end
  end
end
