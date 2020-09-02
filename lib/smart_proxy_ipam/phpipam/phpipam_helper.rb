module PhpipamHelper
  def validate_required_params(required_params, params)
    err = []
    required_params.each do |param|
      if not params[param.to_sym]
        err.push errors[param.to_sym]
      end
    end
    err.length == 0 ? [] : {:code => 400, :error => err}.to_json
  end

  def no_subnets_found?(subnet)
    subnet['error'] && subnet['error'].downcase == "no subnets found"
  end

  def no_section_found?(section)
    section['message'] && section['message'].downcase == "not found"
  end

  def no_sections_found?(sections)
    sections['message'] && sections['message'].downcase == "no sections available"
  end

  def no_free_ip_found?(ip)
    ip['error'] && ip['error'].downcase == "no free addresses found"
  end

  def ip_not_found_in_ipam?(ip)
    ip && ip['message'] && ip['message'].downcase == 'no addresses found'
  end

  def auth_error
    {:code => 401, :error => "Invalid username and password for External IPAM"}.to_json
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

  # Returns a hash with only the fields given in the fields param
  def filter_hash(hash, fields)
    new_hash = {}
    fields.each do |field|
      new_hash[field.to_sym] = hash[field.to_s] if hash[field.to_s]
    end
    new_hash
  end

  def errors
    {
      :cidr => "A 'cidr' parameter for the subnet must be provided(e.g. IPv4: 100.10.10.0/24, IPv6: 2001:db8:abcd:12::/124)",
      :mac => "A 'mac' address must be provided(e.g. 00:0a:95:9d:68:10)",
      :ip => "Missing 'ip' parameter. An IPv4 or IPv6 address must be provided(e.g. IPv4: 100.10.10.22, IPv6: 2001:db8:abcd:12::3)",
      :section_name => "A 'section_name' must be provided",
      :no_connection => "Unable to connect to External IPAM server",
      :no_section => "Group not found in External IPAM"
    }
  end
end
