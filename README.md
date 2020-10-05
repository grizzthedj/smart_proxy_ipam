# smart_proxy_ipam

Foreman Smart Proxy plugin for IPAM integration with various IPAM providers.

Currently supported Providers:
1. [phpIPAM](https://phpipam.net/).
2. [NetBox](https://github.com/netbox-community/netbox).

## Installation

See [How_to_Install_a_Plugin](http://projects.theforeman.org/projects/foreman/wiki/How_to_Install_a_Plugin)
for how to install Foreman plugins

## Usage

Once plugin is installed, you can use an External IPAM to get the next available IP address in subnets.

1. Create a subnet in Foreman of IPAM type "External IPAM". Click on the `Proxy` tab and associate the subnet with a Smart Proxy that has the `externalipam` feature enabled. _NOTE: This subnet must actually exist in External IPAM. There is no integration with subnet creation at this time._
2. Create a host in Foreman. When adding/editing interfaces, select the above created subnet, and the next available IP in the selected subnet will be pulled from phpIPAM, and displayed in the IPv4/IPv6 address field.

### phpIPAM
1. Create a User and API Key in phpIPAM, and ensure they are both named exactly the same. 
2. The "App Security" setting for your API key should be "User token"
3. Add the url and User name and password to the configuration at `/etc/foreman-proxy/settings.d/externalipam_phpipam.yml`

### NetBox
1. Obtain an API token via a user profile in Netbox.
2. Add the token and the url to your NetBox instance to the configuration in `/etc/foreman-proxy/settings.d/externalipam_netbox.yml`

## Local development

1. Clone the Foreman repo
```
git clone https://github.com/theforeman/foreman.git
```
2. Clone the Smart Proxy repo
```
git clone https://github.com/theforeman/smart-proxy
```
3. Fork the Smart Proxy IPAM plugin repo, then clone

smart_proxy_ipam repo: https://github.com/grizzthedj/smart_proxy_ipam

```
git clone https://github.com/<GITHUB_USER>/smart_proxy_ipam
```
4. From Foreman root directory run
```
bundle install
bundle exec rails db:migrate
bundle exec rails db:seed    # This adds 'External IPAM' feature to Features table
bundle exec foreman start
```
5. Add the smart_proxy_ipam plugin to `Gemfile.local.rb` in Smart Proxy bundler.d directory
```
gem 'smart_proxy_ipam', :path => '/path/to/smart_proxy_ipam'
```
6. Copy `config/settings.d/externalipam.yml.example` to `config/settings.d/externalipam.yml`, and set `enabled` to true, and `use_provider` to `externalipam_phpipam` or `externalipam_netbox`.
7. Copy `config/settings.d/externalipam_phpipam.yml.example` to `config/settings.d/externalipam_phpipam.yml` and replace values with your phpIPAM URL and credentials.
8. Copy `config/settings.d/externalipam_netbox.yml.example` to `config/settings.d/externalipam_netbox.yml` and replace values with your Netbox URL and API token.
9. From Smart Proxy root directory run ...
```
bundle install
bundle exec smart-proxy start
```
10. Navigate to Foreman UI at http://localhost:5000
11. Add a Local Smart Proxy in the Foreman UI(Infrastructure => Smart Proxies)
12. Ensure that the `External IPAM` feature is present on the proxy(http://localhost:8000/features)
13. Create a Subnet(IPv4 or IPv6), and associate the subnet with the `External IPAM` proxy. Subnet must exist in phpIPAM.
14. Create a Host, and select an External IPAM Subnet to obtain the next available IP from phpIPAM
NOTE: For IPv6 subnets only, if the subnet has no addresses reserved(i.e. empty), the first address returned is actually the network address(e.g. `fd13:6d20:29dc:cf27::`), which is not a valid IP. This is a bug within phpIPAM itself

## Contributing

Fork and send a Pull Request. Thanks!

## Copyright

Copyright (c) *2020* *Christopher Smith*

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
