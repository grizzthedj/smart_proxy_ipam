
require 'smart_proxy_ipam/ipam_api'

map '/ipam' do
  run Proxy::Ipam::Api
end
