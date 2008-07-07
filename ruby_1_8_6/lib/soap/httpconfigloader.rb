# SOAP4R - HTTP config loader.
# Copyright (C) 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/property'


module SOAP


module HTTPConfigLoader
module_function

  def set_options(client, options)
    client.proxy = options["proxy"]
    options.add_hook("proxy") do |key, value|
      client.proxy = value
    end
    client.no_proxy = options["no_proxy"]
    options.add_hook("no_proxy") do |key, value|
      client.no_proxy = value
    end
    if client.respond_to?(:protocol_version=)
      client.protocol_version = options["protocol_version"]
      options.add_hook("protocol_version") do |key, value|
        client.protocol_version = value
      end
    end
    ssl_config = options["ssl_config"] ||= ::SOAP::Property.new
    set_ssl_config(client, ssl_config)
    ssl_config.add_hook(true) do |key, value|
      set_ssl_config(client, ssl_config)
    end
    basic_auth = options["basic_auth"] ||= ::SOAP::Property.new
    set_basic_auth(client, basic_auth)
    basic_auth.add_hook do |key, value|
      set_basic_auth(client, basic_auth)
    end
    options.add_hook("connect_timeout") do |key, value|
      client.connect_timeout = value
    end
    options.add_hook("send_timeout") do |key, value|
      client.send_timeout = value
    end
    options.add_hook("receive_timeout") do |key, value|
      client.receive_timeout = value
    end
  end

  def set_basic_auth(client, basic_auth)
    basic_auth.values.each do |url, userid, passwd|
      client.set_basic_auth(url, userid, passwd)
    end
  end

  def set_ssl_config(client, ssl_config)
    ssl_config.each do |key, value|
      cfg = client.ssl_config
      if cfg.nil?
        raise NotImplementedError.new("SSL not supported")
      end
      case key
      when 'client_cert'
        cfg.client_cert = cert_from_file(value)
      when 'client_key'
        cfg.client_key = key_from_file(value)
      when 'client_ca'
        cfg.client_ca = value
      when 'ca_path'
        cfg.set_trust_ca(value)
      when 'ca_file'
        cfg.set_trust_ca(value)
      when 'crl'
        cfg.set_crl(value)
      when 'verify_mode'
        cfg.verify_mode = ssl_config_int(value)
      when 'verify_depth'
        cfg.verify_depth = ssl_config_int(value)
      when 'options'
        cfg.options = value
      when 'ciphers'
        cfg.ciphers = value
      when 'verify_callback'
        cfg.verify_callback = value
      when 'cert_store'
        cfg.cert_store = value
      else
        raise ArgumentError.new("unknown ssl_config property #{key}")
      end
    end
  end

  def ssl_config_int(value)
    if value.nil? or value.to_s.empty?
      nil
    else
      begin
        Integer(value)
      rescue ArgumentError
        ::SOAP::Property::Util.const_from_name(value.to_s)
      end
    end
  end

  def cert_from_file(filename)
    OpenSSL::X509::Certificate.new(File.open(filename) { |f| f.read })
  end

  def key_from_file(filename)
    OpenSSL::PKey::RSA.new(File.open(filename) { |f| f.read })
  end
end


end
