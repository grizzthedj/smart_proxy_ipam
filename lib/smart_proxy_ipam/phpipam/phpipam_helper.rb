module PhpipamHelper
  def validate_required_params(required_params, params)
    err = []
    required_params.each do |param|
      if not params[param.to_sym] 
        err.push errors[param.to_sym]
      end
    end
    err.length == 0 ? [] : {:error => err}.to_json
  end

  def no_subnets_found(subnet)
    !subnet.kind_of?(Array) && subnet['message'] && subnet['message'].downcase == "no subnets found"
  end

  def no_section_found(section)
    section['message'] && section['message'].downcase == "not found"
  end

  def no_free_ip_found(ip)
    !ip.kind_of?(Array) && ip['message'] && ip['message'].downcase == "no free addresses found"
  end

  def ip_not_found_in_ipam(ip)
    ip && ip['message'] && ip['message'].downcase == 'no addresses found'
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
      :no_free_ip => "There are no more free addresses in this subnet",
      :no_section => "Section not found in External IPAM.",
      :no_subnet => "The specified subnet does not exist in External IPAM.",
      :no_connection => "Unable to connect to External IPAM server"
    }
  end
end