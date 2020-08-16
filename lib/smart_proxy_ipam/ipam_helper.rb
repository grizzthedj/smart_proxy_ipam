require 'net/http'
# TODO: Refactor & update foreman_ipam plugin with Netbox
# TODO: Update all API documentation in plugin and foreman core(use Swagger docs for plugin?)

# Module containing helper methods for use by all External IPAM provider implementations
module IpamHelper
  def get_provider_instance(provider)
    case provider
    when 'phpipam'
      client = Proxy::Ipam::PhpipamClient.allocate
    when 'netbox'
      client = Proxy::Ipam::NetboxClient.allocate
    else
      # Setting phpIPAM as default provider, when provider not specified,
      # not to break existing implementations
      client = Proxy::Ipam::PhpipamClient.allocate
      # After some time, raise an exception for unknown provider
      # halt 500, { error: 'Unknown IPAM provider' }.to_json
    end

    client.send :initialize
    halt 500, { error: 'Invalid credentials for External IPAM' }.to_json unless client.authenticated?
    client
  end

  def get_ipam_subnet(provider, group_name, cidr)
    subnet = nil

    if group_name.nil? || group_name.empty?
      subnet = provider.get_ipam_subnet(cidr)
    else
      group = provider.get_ipam_group(group_name)
      halt 500, { error: 'Groups are not supported' }.to_json unless provider.groups_supported?
      halt 404, { error: "No group #{group_name} found" }.to_json unless provider.group_exists?(group)
      subnet = provider.get_ipam_subnet(cidr, group[:data][:id])
    end

    subnet
  end

  def increment_ip(ip)
    IPAddr.new(ip.to_s).succ.to_s
  end

  # Checks if given IP is within a subnet. Broadcast address is considered unusable
  def usable_ip(ip, cidr)
    network = IPAddr.new(cidr)
    network.include?(IPAddr.new(ip)) && network.to_range.last != ip
  end

  def validate_presence_of!(required_params, params)
    err = []
    required_params.each do |param|
      unless params[param.to_sym]
        err.push errors[param.to_sym]
      end
    end
    halt 400, { error: err }.to_json unless err.empty?
  end

  def validate_ip!(ip)
    IPAddr.new(ip).to_s
  rescue IPAddr::InvalidAddressError
    nil
  end

  def validate_cidr!(address, prefix)
    cidr = "#{address}/#{prefix}"
    network = IPAddr.new(cidr).to_s
    return nil if network != IPAddr.new(address).to_s
    cidr
  rescue IPAddr::Error
    nil
  end

  def validate_ip_in_cidr!(ip, cidr)
    halt 400, { error: "IP #{ip} is not in subnet #{cidr}" }.to_json unless IPAddr.new(cidr).include?(IPAddr.new(ip))
  end

  def validate_mac!(mac)
    unless mac.match(/^([0-9a-fA-F]{2}[:]){5}[0-9a-fA-F]{2}$/i)
      return nil
    end
    mac
  end

  def get_request_ip(params)
    ip = validate_ip!(params[:ip])
    halt 400, { error: errors[:bad_ip] }.to_json if ip.nil?
    ip
  end

  def get_request_cidr(params)
    cidr = validate_cidr!(params[:address], params[:prefix])
    halt 400, { error: errors[:bad_cidr] }.to_json if cidr.nil?
    cidr
  end

  def get_request_mac(params)
    mac = validate_mac!(params[:mac])
    halt 400, { error: errors[:bad_mac] }.to_json if mac.nil?
    mac
  end

  def get_request_group(params, provider)
    group = params[:group] ? URI.escape(params[:group]) : nil
    halt 500, { error: errors[:groups_not_supported] }.to_json if !provider.groups_supported? && group
    group
  end

  def errors
    {
      cidr: "A 'cidr' parameter for the subnet must be provided(e.g. IPv4: 100.10.10.0/24, IPv6: 2001:db8:abcd:12::/124)",
      mac: "A 'mac' address must be provided(e.g. 00:0a:95:9d:68:10)",
      ip: "Missing 'ip' parameter. An IPv4 or IPv6 address must be provided(e.g. IPv4: 100.10.10.22, IPv6: 2001:db8:abcd:12::3)",
      group_name: "A 'group_name' must be provided",
      no_ip: 'IP address not found',
      no_free_ips: 'No free addresses found',
      no_connection: 'Unable to connect to External IPAM server',
      no_group: 'Group not found in External IPAM',
      no_groups: 'No groups found in External IPAM',
      no_subnet: 'Subnet not found in External IPAM',
      no_subnets_in_group: 'No subnets found in External IPAM group',
      provider: "The IPAM provider must be specified(e.g. 'phpipam' or 'netbox')",
      groups_not_supported: 'Groups are not supported',
      add_ip: 'Error adding IP to External IPAM',
      bad_mac: 'The format of the mac address is invalid',
      bad_ip: 'The format of the ip address is invalid',
      bad_cidr: 'The format of the network cidr is invalid'
    }
  end
end
