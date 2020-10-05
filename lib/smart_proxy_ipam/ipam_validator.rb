require 'resolv'

# Module containing validation methods for use by all External IPAM provider implementations
module Proxy::Ipam::IpamValidator
  include ::Proxy::Validations
  include Proxy::Ipam::IpamHelper

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
    good_ip = ip =~ Regexp.union([Resolv::IPv4::Regex, Resolv::IPv6::Regex])
    raise Proxy::Validations::Error, errors[:bad_ip] if good_ip.nil?
    ip
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
    raise Proxy::Validations::Error.new, errors[:mac] if mac.nil? || mac.empty?
    unless mac.match(/^([0-9a-fA-F]{2}[:]){5}[0-9a-fA-F]{2}$/i)
      raise Proxy::Validations::Error.new, errors[:bad_mac]
    end
    mac
  end
end
