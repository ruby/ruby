=begin
SOAP4R - marshal/unmarshal interface.
Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi.

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

    def marshal(header, body, opt = {}, io = nil)
      env = SOAPEnvelope.new(header, body)
      generator = create_generator(opt)
      generator.generate(env, io)
    end

    def unmarshal(stream, opt = {})
      parser = create_parser(opt)
      env = parser.parse(stream)
      if env
	return env.header, env.body
      else
	return nil, nil
      end
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
