=begin
WSDL4R - Base definitions.
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


require 'xsd/qname'


module WSDL


Version = '0.0.2'

Namespace = 'http://schemas.xmlsoap.org/wsdl/'
SOAPBindingNamespace ='http://schemas.xmlsoap.org/wsdl/soap/'

class Error < StandardError; end


end
