# SOAP4R - EncodingStyle handler library
# Copyright (C) 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
  def decode_typemap=(definedtypes)
    @decode_typemap = definedtypes
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
