
require 'smart_proxy_ipam/phpipam/phpipam_api'
require 'smart_proxy_ipam/ipam/ipam_api'

map '/phpipam' do
  run Proxy::Phpipam::Api
end

map '/ipam' do
  run Proxy::Ipam::Api
end