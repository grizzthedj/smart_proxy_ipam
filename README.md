# smart_proxy_ipam

Foreman Smart Proxy plugin for IPAM integration with various IPAM providers.

Currently supported Providers: 
1. [phpIPAM](https://phpipam.net/). 

Provides a basic Dashboard for viewing phpIPAM sections, subnets. Also supports obtaining of the next available IPv4 address for a given subnet(via [IPAM Smart Proxy Plugin](https://github.com/grizzthedj/smart_proxy_ipam)).


## Installation

See [How_to_Install_a_Plugin](http://projects.theforeman.org/projects/foreman/wiki/How_to_Install_a_Plugin)
for how to install Foreman plugins

## Usage

Once plugin is installed, you can use phpIPAM to get the next available IP address for a subnet:

1. Create a subnet in Foreman of IPAM type "External IPAM". Click on the `Proxy` tab and associate the subnet with a Smart Proxy that has the `External IPAM` feature enabled. _NOTE: This subnet must actually exist in phpIPAM. There is no integration with subnet creation at this time._
2. Create a host in Foreman. When adding/editing interfaces, select the above created subnet, and the next available IP in the selected subnet will be pulled from phpIPAM, and displayed in the IPv4 address field. _NOTE: This is not supported for IPv6._

## Local development

1. Clone the Foreman repo 
```
git clone https://github.com/theforeman/foreman.git
```
2. Clone the Smart Proxy repo
```
git clone https://github.com/theforeman/smart-proxy
```
3. Fork both the foreman plugin and smart proxy plugin repos, then clone

foreman_ipam repo: https://github.com/grizzthedj/foreman_ipam  
smart_proxy_ipam repo: https://github.com/grizzthedj/smart_proxy_ipam

```
git clone https://github.com/<GITHUB_USER>/foreman_ipam
git clone https://github.com/<GITHUB_USER>/smart_proxy_ipam
```
4. Add the foreman_ipam plugin to `Gemfile.local.rb` in the Foreman bundler.d directory
```
gem 'foreman_ipam', :path => '/path/to/foreman_ipam'
```
5. From Foreman root directory run 
```
bundle install
bundle exec rails db:migrate
bundle exec rails db:seed    # This adds 'External IPAM' feature to Features table
bundle exec foreman start
```
6. Add the smart_proxy_ipam plugin to `Gemfile.local.rb` in Smart Proxy bundler.d directory
```
gem 'smart_proxy_ipam', :path => '/path/to/smart_proxy_ipam'
```
7. Copy `config/settings.d/externalipam.yml.example` to `config/settings.d/externalipam.yml` and replace values with your phpIPAM URL and credentials.
8. From Smart Proxy root directory run ... 
```
bundle install
bundle exec smart-proxy start
```
9. Navigate to Foreman UI at http://localhost:5000
10. Add a Local Smart Proxy in the Foreman UI(Infrastructure => Smart Proxies)
11. Ensure that the `External IPAM` feature is present on the proxy(http://localhost:8000/features)
12. Create a Subnet(IPv4 or IPv6), and associate the subnet with the `External IPAM` proxy. Subnet must exist in phpIPAM.
13. Create a Host, and select an External IPAM Subnet to obtain the next available IP from phpIPAM
NOTE: For IPv6 subnets only, if the subnet has no addresses reserved(i.e. empty), the first address returned is actually the network address(e.g. `fd13:6d20:29dc:cf27::`), which is not a valid IP. This is a bug within phpIPAM itself
 
## Contributing

Fork and send a Pull Request. Thanks!

## Copyright

Copyright (c) *2019* *Christopher Smith*

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
