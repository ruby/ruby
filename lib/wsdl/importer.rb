# WSDL4R - WSDL importer library.
# Copyright (C) 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/parser'
require 'soap/soap'


module WSDL


class Importer
  def self.import(location)
    new.import(location)
  end

  def initialize
    @web_client = nil
  end

  def import(location)
    content = nil
    if FileTest.exist?(location)
      content = File.open(location).read
    else
      client = web_client.new(nil, "WSDL4R")
      if env_httpproxy = ::SOAP::Env::HTTP_PROXY
	client.proxy = env_httpproxy
      end
      if env_no_proxy = ::SOAP::Env::NO_PROXY
	client.no_proxy = env_no_proxy
      end
      content = client.get_content(location)
    end
    opt = {}	# charset?
    begin
      WSDL::Parser.new(opt).parse(content)
    rescue WSDL::Parser::ParseError => orgexcn
      begin
	require 'wsdl/xmlSchema/parser'
	WSDL::XMLSchema::Parser.new(opt).parse(content)
      rescue
	raise orgexcn
      end
    end
  end

private

  def web_client
    @web_client ||= begin
	require 'http-access2'
	if HTTPAccess2::VERSION < "2.0"
	  raise LoadError.new("http-access/2.0 or later is required.")
	end
	HTTPAccess2::Client
      rescue LoadError
	STDERR.puts "Loading http-access2 failed.  Net/http is used." if $DEBUG
	require 'soap/netHttpClient'
	::SOAP::NetHttpClient
      end
    @web_client
  end
end


end
