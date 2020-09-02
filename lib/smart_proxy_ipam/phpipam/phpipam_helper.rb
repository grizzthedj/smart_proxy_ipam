module PhpipamHelper
  def validate_required_params!(required_params, params)
    err = required_params.select { |param| params[param] }.map { |param| errors[param] }
    halt 400, {error: err}.to_json unless err.empty?
  end

  def validate_ip!(ip)
    IPAddr.new(ip).to_s
  rescue IPAddr::InvalidAddressError => e
    halt 400, {error: e.to_s}.to_json
  end

  def validate_cidr!(address, prefix)
    cidr = "#{address}/#{prefix}"
    if IPAddr.new(cidr).to_s != IPAddr.new(address).to_s
      halt 400, {error: "Network address #{address} should be #{network} with prefix #{prefix}"}.to_json
    end
    cidr
  rescue IPAddr::Error => e
    halt 400, {error: e.to_s}.to_json
  end

  def validate_ip_in_cidr!(ip, cidr)
    unless IPAddr.new(cidr).include?(IPAddr.new(ip))
      halt 400, {error: "IP #{ip} is not in #{cidr}"}.to_json
    end
  end

  def check_subnet_exists!(subnet)
    if !subnet || subnet['error'] && subnet['error'].downcase == "no subnets found"
      halt 404, {error: 'No subnet found'}.to_json
    end
  end

  def provider
    @provider ||= begin
                    phpipam_client = PhpipamClient.new
                    unless phpipam_client.authenticated?
                      halt 500, {error: 'Invalid username and password for External IPAM'}.to_json
                    end
                    phpipam_client
                  end
  end

  # Returns an array of hashes with only the fields given in the fields param
  def filter_fields(json_body, fields)
    data = []
    json_body['data'].each do |subnet|
      item = {}
      fields.each do |field| item[field.to_sym] = subnet[field.to_s] end
      data.push(item)
    end if json_body && json_body['data']
    data
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
