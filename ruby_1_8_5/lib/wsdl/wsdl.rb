# WSDL4R - Base definitions.
# Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/qname'


module WSDL


Version = '0.0.2'

Namespace = 'http://schemas.xmlsoap.org/wsdl/'
SOAPBindingNamespace ='http://schemas.xmlsoap.org/wsdl/soap/'

class Error < StandardError; end


end
