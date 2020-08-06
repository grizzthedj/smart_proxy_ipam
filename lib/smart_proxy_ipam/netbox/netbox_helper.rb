module NetboxHelper
  def validate_required_params!(required_params, params)
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

  def validate_ip_in_cidr!(ip, cidr)
    halt 400, { error: "IP #{ip} is not in #{cidr}" }.to_json unless IPAddr.new(cidr).include?(IPAddr.new(ip))
  end

  def check_subnet_exists!(subnet)
    halt 404, { error: 'No subnet found' }.to_json if !subnet || subnet['error'] && subnet['error'].downcase == "no subnets found"
  end

  # Returns an array of hashes with only the fields given in the fields param
  def filter_fields(json_body, fields)
    data = []
    json_body[''].each do |subnet|
      item = {}
      fields.each do |field| item[field.to_sym] = subnet[field.to_s] end
      data.push(item)
    end if json_body && json_body['data']
    data
  end
end
