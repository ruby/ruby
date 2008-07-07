# XSD4R - XSD to ruby mapping library.
# Copyright (C) 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/codegen/gensupport'
require 'wsdl/xmlSchema/importer'
require 'wsdl/soap/classDefCreator'


module WSDL
module XMLSchema


class XSD2Ruby
  attr_accessor :location
  attr_reader :opt
  attr_accessor :logger
  attr_accessor :basedir

  def run
    unless @location
      raise RuntimeError, "XML Schema location not given"
    end
    @xsd = import(@location)
    @name = create_classname(@xsd)
    create_file
  end

private

  def initialize
    @location = nil
    @opt = {}
    @logger = Logger.new(STDERR)
    @basedir = nil
    @xsd = nil
    @name = nil
  end

  def create_file
    create_classdef
  end

  def create_classdef
    @logger.info { "Creating class definition." }
    @classdef_filename = @name + '.rb'
    check_file(@classdef_filename) or return
    write_file(@classdef_filename) do |f|
      f << WSDL::SOAP::ClassDefCreator.new(@xsd).dump
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

  def create_classname(xsd)
    name = nil
    if xsd.targetnamespace
      name = xsd.targetnamespace.scan(/[a-zA-Z0-9]+$/)[0]
    end
    if name.nil?
      'default'
    else
      XSD::CodeGen::GenSupport.safevarname(name)
    end
  end

  def import(location)
    WSDL::XMLSchema::Importer.import(location)
  end
end


end
end
