=begin
SOAP4R - EncodingStyle handler library
Copyright (C) 2001, 2003  NAKAMURA, Hiroshi.

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


require 'soap/soap'
require 'soap/baseData'
require 'soap/element'


module SOAP
module EncodingStyle


class Handler
  @@handlers = {}

  class EncodingStyleError < Error; end

  class << self
    def uri
      self::Namespace
    end

    def handler(uri)
      @@handlers[uri]
    end

    def each
      @@handlers.each do |key, value|
	yield(value)
      end
    end

  private

    def add_handler
      @@handlers[self.uri] = self
    end
  end

  attr_reader :charset
  attr_accessor :generate_explicit_type
  def decode_typemap=(complextypes)
    @decode_typemap = complextypes
  end

  def initialize(charset)
    @charset = charset
    @generate_explicit_type = true
    @decode_typemap = nil
  end

  ###
  ## encode interface.
  #
  # Returns a XML instance as a string.
  def encode_data(generator, ns, qualified, data, parent)
    raise NotImplementError.new('Method encode_data must be defined in derived class.')
  end

  def encode_data_end(generator, ns, qualified, data, parent)
    raise NotImplementError.new('Method encode_data must be defined in derived class.')
  end

  def encode_prologue
  end

  def encode_epilogue
  end

  ###
  ## decode interface.
  #
  # Returns SOAP/OM data.
  def decode_tag(ns, name, attrs, parent)
    raise NotImplementError.new('Method decode_tag must be defined in derived class.')
  end

  def decode_tag_end(ns, name)
    raise NotImplementError.new('Method decode_tag_end must be defined in derived class.')
  end

  def decode_text(ns, text)
    raise NotImplementError.new('Method decode_text must be defined in derived class.')
  end

  def decode_prologue
  end

  def decode_epilogue
  end
end


end
end
