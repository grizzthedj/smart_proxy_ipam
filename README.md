# smart_proxy_ipam

Foreman Smart Proxy plugin for IPAM integration with various IPAM providers.

Currently supported Providers: 
1. [phpIPAM](https://phpipam.net/). 

Provides a basic Dashboard for viewing phpIPAM sections, subnets. Also supports obtaining of the next available IPv4 address for a given subnet(via [IPAM Smart Proxy Plugin](https://github.com/grizzthedj/smart_proxy_ipam)).


## Installation

See [How_to_Install_a_Plugin](http://projects.theforeman.org/projects/foreman/wiki/How_to_Install_a_Plugin)
for how to install Foreman plugins

## Usage

Once plugin is installed, you can look at the phpIPAM Dashboard(at Infrastructure --> phpIPAM Dashboard), for a simple view of sections, subnets etc. and/or use phpIPAM to get the next available IP address for a subnet:

1. Create a subnet in Foreman of IPAM type "phpIPAM". Click on the `Proxy` tab and associate the subnet with the phpIPAM proxy. _NOTE: This subnet must actually exist in phpIPAM. There is no phpIPAM integration on the subnet creation at this time._
2. Create a host in Foreman. When adding/editing interfaces, select the above subnet, and the next available IP(pulled from phpIPAM) for the selected subnet will be displayed in the IPv4 address field. _NOTE: This is not supported for IPv6._

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

foreman_phpipam repo: https://github.com/grizzthedj/smart_proxy_phpipam  
smart_proxy_phpipam repo: https://github.com/grizzthedj/smart_proxy_phpipam

```
git clone https://github.com/<GITHUB_USER>/foreman_phpipam
git clone https://github.com/<GITHUB_USER>/smart_proxy_phpipam
```
4. Add the foreman_phpipam plugin to `Gemfile.local.rb` in the Foreman bundler.d directory
```
gem 'foreman_phpipam', :path => '/path/to/foreman_phpipam'
```
5. From Foreman root directory run 
```
bundle install
bundle exec rails db:migrate
bundle exec rails db:seed    # This adds 'phpIPAM' feature to Features table
bundle exec foreman start
```
6. Add the smart_proxy_phpipam plugin to `Gemfile.local.rb` in Smart Proxy bundler.d directory
```
gem 'smart_proxy_phpipam', :path => '/path/to/smart_proxy_phpipam'
```
7. Copy `config/settings.d/phpipam.yml.example` to `config/settings.d/phpipam.yml` and replace values with your phpIPAM URL and credentials.
8. From Smart Proxy root directory run ... 
```
bundle install
bundle exec smart-proxy start
```
9. Navigate to Foreman UI at http://localhost:5000
10. Add a Local Smart Proxy in the Foreman UI(Infrastructure => Smart Proxies)
11. Ensure that the `phpipam` feature is present on the proxy(http://proxy_url/features)
12. Create a Subnet, and associate the subnet to the `phpipam` proxy
 
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
