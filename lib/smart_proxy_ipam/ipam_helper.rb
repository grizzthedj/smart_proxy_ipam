require 'net/http'

  # - [DONE] -: Look at get_subnet_by_group() in phpipam client in BitBucket to troubleshoot
  # - [DONE] -: Move common HTTP methods(GET, POST etc.) into module
  # - [DONE] -: Move IP cache code into module
  # - [DONE] -: Add provider layer to cache
  # - [DONE] -: Use halt 500 for validation, and use module for validation

  # TODO: Add rubocop
  # TODO: Move common HTTP parsing into module
  # TODO: Make error handling consistent(using halt 500 etc.), and test in Foreman
  # TODO: @api_base should be specific to provider
  # TODO: Refactor & update foreman_ipam plugin with Netbox
  # TODO: Update all API documentation(use Swagger docs?)
  # TODO: Remove things like this from ipam_api(e.g. group['data']['id'].to_s)
  # TODO: Fix/add tests

module IpamHelper
  def get_instance(provider)
    case provider 
    when "phpipam"
      client = Proxy::Ipam::PhpipamClient.allocate
    when "netbox"
      client = Proxy::Ipam::NetboxClient.allocate
    else 
      # Set to phpIPAM as a default, not to break existing implementations. After some
      # time, raise an exception for unknown provider
      client = Proxy::Ipam::PhpipamClient.allocate
      # halt 500, {error: 'Unknown IPAM provider'}.to_json
    end

    client.send :initialize

    unless client.authenticated?
      halt 500, {error: 'Invalid username and password for External IPAM'}.to_json
    end

    client
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
    halt 400, {error: err}.to_json unless err.empty?
  end
  
  def validate_ip!(ip)
    IPAddr.new(ip).to_s
  rescue IPAddr::InvalidAddressError => e
    halt 400, { error: e.to_s }.to_json
  end

  def validate_cidr!(address, prefix)
    cidr = "#{address}/#{prefix}"
    network = IPAddr.new(cidr).to_s

    if network != IPAddr.new(address).to_s
      halt 400, { error: "Network address #{address} should be #{network} with prefix #{prefix}" }.to_json
    end

    cidr
  rescue IPAddr::Error => e
    halt 400, { error: e.to_s }.to_json
  end

  def errors
    {
      :cidr => "A 'cidr' parameter for the subnet must be provided(e.g. IPv4: 100.10.10.0/24, IPv6: 2001:db8:abcd:12::/124)",
      :mac => "A 'mac' address must be provided(e.g. 00:0a:95:9d:68:10)",
      :ip => "Missing 'ip' parameter. An IPv4 or IPv6 address must be provided(e.g. IPv4: 100.10.10.22, IPv6: 2001:db8:abcd:12::3)",
      :group_name => "A 'group_name' must be provided",
      :no_ip => "IP address not found",
      :no_connection => "Unable to connect to External IPAM server",
      :no_group => "Group not found in External IPAM",
      :no_subnet => "Subnet not found in External IPAM",
      :no_subnets_in_group => "No subnets found in External IPAM group",
      :provider => "The IPAM provider must be specified(e.g. 'phpipam' or 'netbox')",
      :groups_not_supported => "Groups are not supported"
    }
  end
end