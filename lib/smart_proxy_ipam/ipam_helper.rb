# Module containing helper methods for use by all External IPAM provider implementations
module Proxy::Ipam::IpamHelper
  include ::Proxy::Validations

  def get_ipam_subnet(group_name, cidr)
    subnet = nil

    if group_name.nil? || group_name.empty?
      subnet = provider.get_ipam_subnet(cidr)
    else
      group = provider.get_ipam_group(group_name)
      halt 500, { error: 'Groups are not supported' }.to_json unless provider.groups_supported?
      halt 404, { error: "No group #{group_name} found" }.to_json if group.nil?
      subnet = provider.get_ipam_subnet(cidr, group[:id])
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

  def validate_required_params!(required_params, params)
    err = []
    required_params.each do |param|
      unless params[param.to_sym]
        err.push errors[param.to_sym]
      end
    end
    raise Proxy::Validations::Error, err unless err.empty?
  end

  def validate_ip!(ip)
    IPAddr.new(ip).to_s
  rescue IPAddr::InvalidAddressError => e
    raise Proxy::Validations::Error, e.to_s
  end

  def validate_cidr!(address, prefix)
    cidr = "#{address}/#{prefix}"
    network = IPAddr.new(cidr).to_s
    if IPAddr.new(cidr).to_s != IPAddr.new(address).to_s
      raise Proxy::Validations::Error, "Network address #{address} should be #{network} with prefix #{prefix}"
    end
    cidr
  rescue IPAddr::Error => e
    raise Proxy::Validations::Error, e.to_s
  end

  def validate_ip_in_cidr!(ip, cidr)
    unless IPAddr.new(cidr).include?(IPAddr.new(ip))
      raise Proxy::Validations::Error.new, "IP #{ip} is not in #{cidr}"
    end
  end

  def validate_mac!(mac)
    unless mac.match(/^([0-9a-fA-F]{2}[:]){5}[0-9a-fA-F]{2}$/i)
      raise Proxy::Validations::Error.new, 'Mac address is not valid'
    end
    mac
  end

  def provider
    @provider ||=
      begin
        unless client.authenticated?
          halt 500, {error: 'Invalid credentials for External IPAM'}.to_json
        end
        client
      end
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

  def get_request_group(params)
    group = params[:group] ? URI.escape(params[:group]) : nil
    halt 500, { error: errors[:groups_not_supported] }.to_json if group && !provider.groups_supported?
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
      bad_mac: 'Mac address is invalid',
      bad_ip: 'IP address is invalid',
      bad_cidr: 'The network cidr is invalid'
    }
  end
end
