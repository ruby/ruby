# SOAP4R - marshal/unmarshal interface.
# Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/datatypes'
require 'soap/soap'
require 'soap/element'
require 'soap/parser'
require 'soap/generator'
require 'soap/encodingstyle/soapHandler'
require 'soap/encodingstyle/literalHandler'
require 'soap/encodingstyle/aspDotNetHandler'


module SOAP


module Processor
  @@default_parser_option = {}

  class << self
  public

    def marshal(env, opt = {}, io = nil)
      generator = create_generator(opt)
      marshalled_str = generator.generate(env, io)
      unless env.external_content.empty?
	opt[:external_content] = env.external_content
      end
      marshalled_str
    end

    def unmarshal(stream, opt = {})
      parser = create_parser(opt)
      parser.parse(stream)
    end

    def default_parser_option=(rhs)
      @@default_parser_option = rhs
    end

    def default_parser_option
      @@default_parser_option
    end

  private

    def create_generator(opt)
      SOAPGenerator.new(opt)
    end

    def create_parser(opt)
      if opt.empty?
	opt = @@default_parser_option
      end
      ::SOAP::Parser.new(opt)
    end
  end
end


end
