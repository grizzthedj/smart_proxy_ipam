module Proxy::Ipam
  extend ::Proxy::Util
  extend ::Proxy::Log

  class << self
    def get_config
      Proxy::Ipam::Plugin.settings.externalipam
    end
  end
end
