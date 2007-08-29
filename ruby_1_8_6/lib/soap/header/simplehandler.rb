# SOAP4R - SOAP Simple header item handler
# Copyright (C) 2003-2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/header/handler'
require 'soap/baseData'


module SOAP
module Header


class SimpleHandler < SOAP::Header::Handler
  def initialize(elename)
    super(elename)
  end

  # Should return a Hash, String or nil.
  def on_simple_outbound
    nil
  end

  # Given header is a Hash, String or nil.
  def on_simple_inbound(header, mustunderstand)
  end

  def on_outbound
    h = on_simple_outbound
    h ? SOAPElement.from_obj(h, elename.namespace) : nil
  end

  def on_inbound(header, mustunderstand)
    h = header.respond_to?(:to_obj) ? header.to_obj : header.data
    on_simple_inbound(h, mustunderstand)
  end
end


end
end
