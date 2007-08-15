# SOAP4R - SOAP Header handler item
# Copyright (C) 2003, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/element'


module SOAP
module Header


class Handler
  attr_reader :elename
  attr_reader :mustunderstand
  attr_reader :encodingstyle

  def initialize(elename)
    @elename = elename
    @mustunderstand = false
    @encodingstyle = nil
  end

  # Should return a SOAP/OM, a SOAPHeaderItem or nil.
  def on_outbound
    nil
  end

  # Given header is a SOAPHeaderItem or nil.
  def on_inbound(header, mustunderstand = false)
    # do something.
  end

  def on_outbound_headeritem
    item = on_outbound
    if item.nil?
      nil
    elsif item.is_a?(::SOAP::SOAPHeaderItem)
      item.elename = @elename
      item
    else
      item.elename = @elename
      ::SOAP::SOAPHeaderItem.new(item, @mustunderstand, @encodingstyle)
    end
  end

  def on_inbound_headeritem(header)
    on_inbound(header.element, header.mustunderstand)
  end
end


end
end
