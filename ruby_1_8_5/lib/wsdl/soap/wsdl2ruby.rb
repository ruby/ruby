# WSDL4R - WSDL to ruby mapping library.
# Copyright (C) 2002-2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'logger'
require 'xsd/qname'
require 'wsdl/importer'
require 'wsdl/soap/classDefCreator'
require 'wsdl/soap/servantSkeltonCreator'
require 'wsdl/soap/driverCreator'
require 'wsdl/soap/clientSkeltonCreator'
require 'wsdl/soap/standaloneServerStubCreator'
require 'wsdl/soap/cgiStubCreator'


module WSDL
module SOAP


class WSDL2Ruby
  attr_accessor :location
  attr_reader :opt
  attr_accessor :logger
  attr_accessor :basedir

  def run
    unless @location
      raise RuntimeError, "WSDL location not given"
    end
    @wsdl = import(@location)
    @name = @wsdl.name ? @wsdl.name.name : 'default'
    create_file
  end

private

  def initialize
    @location = nil
    @opt = {}
    @logger = Logger.new(STDERR)
    @basedir = nil
    @wsdl = nil
    @name = nil
  end

  def create_file
    create_classdef if @opt.key?('classdef')
    create_servant_skelton(@opt['servant_skelton']) if @opt.key?('servant_skelton')
    create_cgi_stub(@opt['cgi_stub']) if @opt.key?('cgi_stub')
    create_standalone_server_stub(@opt['standalone_server_stub']) if @opt.key?('standalone_server_stub')
    create_driver(@opt['driver']) if @opt.key?('driver')
    create_client_skelton(@opt['client_skelton']) if @opt.key?('client_skelton')
  end

  def create_classdef
    @logger.info { "Creating class definition." }
    @classdef_filename = @name + '.rb'
    check_file(@classdef_filename) or return
    write_file(@classdef_filename) do |f|
      f << WSDL::SOAP::ClassDefCreator.new(@wsdl).dump
    end
  end

  def create_client_skelton(servicename)
    @logger.info { "Creating client skelton." }
    servicename ||= @wsdl.services[0].name.name
    @client_skelton_filename = servicename + 'Client.rb'
    check_file(@client_skelton_filename) or return
    write_file(@client_skelton_filename) do |f|
      f << shbang << "\n"
      f << "require '#{@driver_filename}'\n\n" if @driver_filename
      f << WSDL::SOAP::ClientSkeltonCreator.new(@wsdl).dump(
	create_name(servicename))
    end
  end

  def create_servant_skelton(porttypename)
    @logger.info { "Creating servant skelton." }
    @servant_skelton_filename = (porttypename || @name + 'Servant') + '.rb'
    check_file(@servant_skelton_filename) or return
    write_file(@servant_skelton_filename) do |f|
      f << "require '#{@classdef_filename}'\n\n" if @classdef_filename
      f << WSDL::SOAP::ServantSkeltonCreator.new(@wsdl).dump(
	create_name(porttypename))
    end
  end

  def create_cgi_stub(servicename)
    @logger.info { "Creating CGI stub." }
    servicename ||= @wsdl.services[0].name.name
    @cgi_stubFilename = servicename + '.cgi'
    check_file(@cgi_stubFilename) or return
    write_file(@cgi_stubFilename) do |f|
      f << shbang << "\n"
      if @servant_skelton_filename
	f << "require '#{@servant_skelton_filename}'\n\n"
      end
      f << WSDL::SOAP::CGIStubCreator.new(@wsdl).dump(create_name(servicename))
    end
  end

  def create_standalone_server_stub(servicename)
    @logger.info { "Creating standalone stub." }
    servicename ||= @wsdl.services[0].name.name
    @standalone_server_stub_filename = servicename + '.rb'
    check_file(@standalone_server_stub_filename) or return
    write_file(@standalone_server_stub_filename) do |f|
      f << shbang << "\n"
      f << "require '#{@servant_skelton_filename}'\n\n" if @servant_skelton_filename
      f << WSDL::SOAP::StandaloneServerStubCreator.new(@wsdl).dump(
	create_name(servicename))
    end
  end

  def create_driver(porttypename)
    @logger.info { "Creating driver." }
    @driver_filename = (porttypename || @name) + 'Driver.rb'
    check_file(@driver_filename) or return
    write_file(@driver_filename) do |f|
      f << "require '#{@classdef_filename}'\n\n" if @classdef_filename
      f << WSDL::SOAP::DriverCreator.new(@wsdl).dump(
	create_name(porttypename))
    end
  end

  def write_file(filename)
    if @basedir
      filename = File.join(basedir, filename)
    end
    File.open(filename, "w") do |f|
      yield f
    end
  end

  def check_file(filename)
    if @basedir
      filename = File.join(basedir, filename)
    end
    if FileTest.exist?(filename)
      if @opt.key?('force')
	@logger.warn {
	  "File '#{filename}' exists but overrides it."
	}
	true
      else
	@logger.warn {
	  "File '#{filename}' exists.  #{$0} did not override it."
	}
	false
      end
    else
      @logger.info { "Creates file '#{filename}'." }
      true
    end
  end

  def shbang
    "#!/usr/bin/env ruby"
  end

  def create_name(name)
    name ? XSD::QName.new(@wsdl.targetnamespace, name) : nil
  end

  def import(location)
    WSDL::Importer.import(location)
  end
end


end
end
