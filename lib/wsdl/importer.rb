# WSDL4R - WSDL importer library.
# Copyright (C) 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/parser'


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
      proxy = ENV['http_proxy'] || ENV['HTTP_PROXY']
      content = web_client.new(proxy, "WSDL4R").get_content(location)
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
