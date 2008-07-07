# SOAP4R - SOAP Header handler set
# Copyright (C) 2003, 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/namedelements'


module SOAP
module Header


class HandlerSet
  def initialize
    @store = XSD::NamedElements.new
  end

  def dup
    obj = HandlerSet.new
    obj.store = @store.dup
    obj
  end

  def add(handler)
    @store << handler
  end
  alias << add

  def delete(handler)
    @store.delete(handler)
  end

  def include?(handler)
    @store.include?(handler)
  end

  # returns: Array of SOAPHeaderItem
  def on_outbound
    @store.collect { |handler|
      handler.on_outbound_headeritem
    }.compact
  end

  # headers: SOAPHeaderItem enumerable object
  def on_inbound(headers)
    headers.each do |name, item|
      handler = @store.find { |handler|
        handler.elename == item.element.elename
      }
      if handler
        handler.on_inbound_headeritem(item)
      elsif item.mustunderstand
        raise UnhandledMustUnderstandHeaderError.new(item.element.elename.to_s)
      end
    end
  end

protected

  def store=(store)
    @store = store
  end
end


end
end
