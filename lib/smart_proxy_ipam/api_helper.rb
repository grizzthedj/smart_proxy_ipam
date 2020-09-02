module Proxy::Ipam::ApiHelper
  def validate_required_params!(required_params, params)
    err = required_params.select { |param| params[param] }.map { |param| errors[param] }
    raise Proxy::Validations::Error, err unless err.empty?
  end

  def validate_ip!(ip)
    IPAddr.new(ip).to_s
  rescue IPAddr::InvalidAddressError => e
    raise Proxy::Validations::Error, e.to_s
  end

  def validate_cidr!(address, prefix)
    cidr = "#{address}/#{prefix}"
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

  def check_subnet_exists!(subnet)
    if !subnet || subnet['error'] && subnet['error'].downcase == "no subnets found"
      halt 404, {error: 'No subnet found'}.to_json
    end
  end

  def provider
    @provider ||= begin
                    unless client.authenticated?
                      halt 500, {error: 'Invalid username and password for External IPAM'}.to_json
                    end
                    client
                  end
  end

  def errors
    {
      :cidr => "A 'cidr' parameter for the subnet must be provided(e.g. IPv4: 100.10.10.0/24, IPv6: 2001:db8:abcd:12::/124)",
      :mac => "A 'mac' address must be provided(e.g. 00:0a:95:9d:68:10)",
      :ip => "Missing 'ip' parameter. An IPv4 or IPv6 address must be provided(e.g. IPv4: 100.10.10.22, IPv6: 2001:db8:abcd:12::3)",
      :section_name => "A 'section_name' must be provided",
      :no_section => "Group not found in External IPAM"
    }
  end
end
