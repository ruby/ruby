# SOAP4R - Stream handler.
# Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/property'
begin
  require 'stringio'
  require 'zlib'
rescue LoadError
  STDERR.puts "Loading stringio or zlib failed.  No gzipped response support." if $DEBUG
end


module SOAP


class StreamHandler
  Client = begin
      require 'http-access2'
      if HTTPAccess2::VERSION < "2.0"
	raise LoadError.new("http-access/2.0 or later is required.")
      end
      HTTPAccess2::Client
    rescue LoadError
      STDERR.puts "Loading http-access2 failed.  Net/http is used." if $DEBUG
      require 'soap/netHttpClient'
      SOAP::NetHttpClient
    end

  RUBY_VERSION_STRING = "ruby #{ RUBY_VERSION } (#{ RUBY_RELEASE_DATE }) [#{ RUBY_PLATFORM }]"

  class ConnectionData
    attr_accessor :send_string
    attr_accessor :send_contenttype
    attr_accessor :receive_string
    attr_accessor :receive_contenttype
    attr_accessor :is_fault

    def initialize(send_string = nil)
      @send_string = send_string
      @send_contenttype = nil
      @receive_string = nil
      @receive_contenttype = nil
      @is_fault = false
    end
  end

  def self.parse_media_type(str)
    if /^#{ MediaType }(?:\s*;\s*charset=([^"]+|"[^"]+"))?$/i !~ str
      return nil
    end
    charset = $1
    charset.gsub!(/"/, '') if charset
    charset || 'us-ascii'
  end

  def self.create_media_type(charset)
    "#{ MediaType }; charset=#{ charset }"
  end
end


class HTTPStreamHandler < StreamHandler
  include SOAP

public
  
  attr_reader :client
  attr_accessor :wiredump_file_base
  
  NofRetry = 10       	# [times]

  def initialize(options)
    super()
    @client = Client.new(nil, "SOAP4R/#{ Version }")
    @wiredump_file_base = nil
    @charset = @wiredump_dev = @nil
    @options = options
    set_options
    @client.debug_dev = @wiredump_dev
    @cookie_store = nil
    @accept_encoding_gzip = false
  end

  def test_loopback_response
    @client.test_loopback_response
  end

  def accept_encoding_gzip=(allow)
    @accept_encoding_gzip = allow
  end

  def inspect
    "#<#{self.class}>"
  end

  def send(endpoint_url, conn_data, soapaction = nil, charset = @charset)
    send_post(endpoint_url, conn_data, soapaction, charset)
  end

  def reset(endpoint_url = nil)
    if endpoint_url.nil?
      @client.reset_all
    else
      @client.reset(endpoint_url)
    end
    @client.save_cookie_store if @cookie_store
  end

private

  def set_options
    @client.proxy = @options["proxy"]
    @options.add_hook("proxy") do |key, value|
      @client.proxy = value
    end
    @client.no_proxy = @options["no_proxy"]
    @options.add_hook("no_proxy") do |key, value|
      @client.no_proxy = value
    end
    if @client.respond_to?(:protocol_version=)
      @client.protocol_version = @options["protocol_version"]
      @options.add_hook("protocol_version") do |key, value|
	@client.protocol_version = value
      end
    end
    set_cookie_store_file(@options["cookie_store_file"])
    @options.add_hook("cookie_store_file") do |key, value|
      set_cookie_store_file(value)
    end
    @charset = @options["charset"] || XSD::Charset.charset_label($KCODE)
    @options.add_hook("charset") do |key, value|
      @charset = value
    end
    @wiredump_dev = @options["wiredump_dev"]
    @options.add_hook("wiredump_dev") do |key, value|
      @wiredump_dev = value
      @client.debug_dev = @wiredump_dev
    end
    ssl_config = @options["ssl_config"] ||= ::SOAP::Property.new
    set_ssl_config(ssl_config)
    ssl_config.add_hook(true) do |key, value|
      set_ssl_config(ssl_config)
    end
    basic_auth = @options["basic_auth"] ||= ::SOAP::Property.new
    set_basic_auth(basic_auth)
    basic_auth.add_hook do |key, value|
      set_basic_auth(basic_auth)
    end
    @options.add_hook("connect_timeout") do |key, value|
      @client.connect_timeout = value
    end
    @options.add_hook("send_timeout") do |key, value|
      @client.send_timeout = value
    end
    @options.add_hook("receive_timeout") do |key, value|
      @client.receive_timeout = value
    end
    @options.lock(true)
    ssl_config.unlock
    basic_auth.unlock
  end

  def set_basic_auth(basic_auth)
    basic_auth.values.each do |url, userid, passwd|
      @client.set_basic_auth(url, userid, passwd)
    end
  end

  def set_cookie_store_file(value)
    @cookie_store = value
    @client.set_cookie_store(@cookie_store) if @cookie_store
  end

  def set_ssl_config(ssl_config)
    ssl_config.each do |key, value|
      cfg = @client.ssl_config
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
    if value.nil? or value.empty?
      nil
    else
      begin
        Integer(value)
      rescue ArgumentError
        ::SOAP::Property::Util.const_from_name(value)
      end
    end
  end

  def cert_from_file(filename)
    OpenSSL::X509::Certificate.new(File.open(filename) { |f| f.read })
  end

  def key_from_file(filename)
    OpenSSL::PKey::RSA.new(File.open(filename) { |f| f.read })
  end

  def send_post(endpoint_url, conn_data, soapaction, charset)
    conn_data.send_contenttype ||= StreamHandler.create_media_type(charset)

    if @wiredump_file_base
      filename = @wiredump_file_base + '_request.xml'
      f = File.open(filename, "w")
      f << conn_data.send_string
      f.close
    end

    extra = {}
    extra['Content-Type'] = conn_data.send_contenttype
    extra['SOAPAction'] = "\"#{ soapaction }\""
    extra['Accept-Encoding'] = 'gzip' if send_accept_encoding_gzip?
    send_string = conn_data.send_string
    @wiredump_dev << "Wire dump:\n\n" if @wiredump_dev
    begin
      res = @client.post(endpoint_url, send_string, extra)
    rescue
      @client.reset(endpoint_url)
      raise
    end
    @wiredump_dev << "\n\n" if @wiredump_dev
    receive_string = res.content
    if @wiredump_file_base
      filename = @wiredump_file_base + '_response.xml'
      f = File.open(filename, "w")
      f << receive_string
      f.close
    end
    case res.status
    when 405
      raise PostUnavailableError.new("#{ res.status }: #{ res.reason }")
    when 200, 500
      # Nothing to do.
    else
      raise HTTPStreamError.new("#{ res.status }: #{ res.reason }")
    end
    if res.respond_to?(:header) and !res.header['content-encoding'].empty? and
        res.header['content-encoding'][0].downcase == 'gzip'
      receive_string = decode_gzip(receive_string)
    end
    conn_data.receive_string = receive_string
    conn_data.receive_contenttype = res.contenttype
    conn_data
  end

  def send_accept_encoding_gzip?
    @accept_encoding_gzip and defined?(::Zlib)
  end

  def decode_gzip(instring)
    unless send_accept_encoding_gzip?
      raise HTTPStreamError.new("Gzipped response content.")
    end
    begin
      gz = Zlib::GzipReader.new(StringIO.new(instring))
      gz.read
    ensure
      gz.close
    end
  end
end


end
