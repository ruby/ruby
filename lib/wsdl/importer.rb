=begin
WSDL4R - WSDL importer library.
Copyright (C) 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'wsdl/info'


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
