require 'sinatra'
require 'smart_proxy_ipam/ipam'
require 'smart_proxy_ipam/ipam_main'

module Proxy::Ipam
  class Api < ::Sinatra::Base
    include ::Proxy::Log
    helpers ::Proxy::Helpers

    get '/providers' do
      content_type :json
      {ipam_providers: ['phpIPAM']}.to_json
    end
  end
end