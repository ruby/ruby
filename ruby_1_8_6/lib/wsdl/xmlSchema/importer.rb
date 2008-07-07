# WSDL4R - XSD importer library.
# Copyright (C) 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/httpconfigloader'
require 'wsdl/xmlSchema/parser'


module WSDL
module XMLSchema


class Importer
  def self.import(location, originalroot = nil)
    new.import(location, originalroot)
  end

  def initialize
    @web_client = nil
  end

  def import(location, originalroot = nil)
    unless location.is_a?(URI)
      location = URI.parse(location)
    end
    content = parse(fetch(location), location, originalroot)
    content.location = location
    content
  end

private

  def parse(content, location, originalroot)
    opt = {
      :location => location,
      :originalroot => originalroot
    }
    WSDL::XMLSchema::Parser.new(opt).parse(content)
  end

  def fetch(location)
    warn("importing: #{location}") if $DEBUG
    content = nil
    if location.scheme == 'file' or
        (location.relative? and FileTest.exist?(location.path))
      content = File.open(location.path).read
    elsif location.scheme and location.scheme.size == 1 and
        FileTest.exist?(location.to_s)
      # ToDo: remove this ugly workaround for a path with drive letter
      # (D://foo/bar)
      content = File.open(location.to_s).read
    else
      client = web_client.new(nil, "WSDL4R")
      client.proxy = ::SOAP::Env::HTTP_PROXY
      client.no_proxy = ::SOAP::Env::NO_PROXY
      if opt = ::SOAP::Property.loadproperty(::SOAP::PropertyName)
        ::SOAP::HTTPConfigLoader.set_options(client,
          opt["client.protocol.http"])
      end
      content = client.get_content(location)
    end
    content
  end

  def web_client
    @web_client ||= begin
	require 'http-access2'
	if HTTPAccess2::VERSION < "2.0"
	  raise LoadError.new("http-access/2.0 or later is required.")
	end
	HTTPAccess2::Client
      rescue LoadError
	warn("Loading http-access2 failed.  Net/http is used.") if $DEBUG
	require 'soap/netHttpClient'
	::SOAP::NetHttpClient
      end
    @web_client
  end
end


end
end
