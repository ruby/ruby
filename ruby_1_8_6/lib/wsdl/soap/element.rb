# WSDL4R - XMLSchema element definition for WSDL.
# Copyright (C) 2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/xmlSchema/element'


module WSDL
module XMLSchema


class Element < Info
  def map_as_array?
    maxoccurs != '1'
  end

  def attributes
    @local_complextype.attributes
  end
end


end
end
