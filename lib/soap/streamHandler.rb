# SOAP4R - Stream handler.
# Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/httpconfigloader'
begin
  require 'stringio'
  require 'zlib'
rescue LoadError
  warn("Loading stringio or zlib failed.  No gzipped response support.") if $DEBUG
end


module SOAP


class StreamHandler
  RUBY_VERSION_STRING = "ruby #{ RUBY_VERSION } (#{ RUBY_RELEASE_DATE }) [#{ RUBY_PLATFORM }]"

  class ConnectionData
    attr_accessor :send_string
    attr_accessor :send_contenttype
    attr_accessor :receive_string
    attr_accessor :receive_contenttype
    attr_accessor :is_fault
    attr_accessor :soapaction

    def initialize(send_string = nil)
      @send_string = send_string
      @send_contenttype = nil
      @receive_string = nil
      @receive_contenttype = nil
      @is_fault = false
      @soapaction = nil
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

  begin
    require 'http-access2'
    if HTTPAccess2::VERSION < "2.0"
      raise LoadError.new("http-access/2.0 or later is required.")
    end
    Client = HTTPAccess2::Client
    RETRYABLE = true
  rescue LoadError
    warn("Loading http-access2 failed.  Net/http is used.") if $DEBUG
    require 'soap/netHttpClient'
    Client = SOAP::NetHttpClient
    RETRYABLE = false
  end


public

  attr_reader :client
  attr_accessor :wiredump_file_base

  MAX_RETRY_COUNT = 10       	# [times]

  def initialize(options)
    super()
    @client = Client.new(nil, "SOAP4R/#{ Version }")
    @wiredump_file_base = nil
    @charset = @wiredump_dev = nil
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
    conn_data.soapaction ||= soapaction # for backward conpatibility
    send_post(endpoint_url, conn_data, charset)
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
    HTTPConfigLoader.set_options(@client, @options)
    @charset = @options["charset"] || XSD::Charset.xml_encoding_label
    @options.add_hook("charset") do |key, value|
      @charset = value
    end
    @wiredump_dev = @options["wiredump_dev"]
    @options.add_hook("wiredump_dev") do |key, value|
      @wiredump_dev = value
      @client.debug_dev = @wiredump_dev
    end
    set_cookie_store_file(@options["cookie_store_file"])
    @options.add_hook("cookie_store_file") do |key, value|
      set_cookie_store_file(value)
    end
    ssl_config = @options["ssl_config"]
    basic_auth = @options["basic_auth"]
    @options.lock(true)
    ssl_config.unlock
    basic_auth.unlock
  end

  def set_cookie_store_file(value)
    value = nil if value and value.empty?
    @cookie_store = value
    @client.set_cookie_store(@cookie_store) if @cookie_store
  end

  def send_post(endpoint_url, conn_data, charset)
    conn_data.send_contenttype ||= StreamHandler.create_media_type(charset)

    if @wiredump_file_base
      filename = @wiredump_file_base + '_request.xml'
      f = File.open(filename, "w")
      f << conn_data.send_string
      f.close
    end

    extra = {}
    extra['Content-Type'] = conn_data.send_contenttype
    extra['SOAPAction'] = "\"#{ conn_data.soapaction }\""
    extra['Accept-Encoding'] = 'gzip' if send_accept_encoding_gzip?
    send_string = conn_data.send_string
    @wiredump_dev << "Wire dump:\n\n" if @wiredump_dev
    begin
      retry_count = 0
      while true
        res = @client.post(endpoint_url, send_string, extra)
        if RETRYABLE and HTTP::Status.redirect?(res.status)
          retry_count += 1
          if retry_count >= MAX_RETRY_COUNT
            raise HTTPStreamError.new("redirect count exceeded")
          end
          endpoint_url = res.header["location"][0]
          puts "redirected to #{endpoint_url}" if $DEBUG
        else
          break
        end
      end
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
