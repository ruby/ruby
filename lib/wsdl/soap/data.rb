# WSDL4R - WSDL SOAP binding data definitions.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/qname'
require 'wsdl/soap/definitions'
require 'wsdl/soap/binding'
require 'wsdl/soap/operation'
require 'wsdl/soap/body'
require 'wsdl/soap/element'
require 'wsdl/soap/header'
require 'wsdl/soap/headerfault'
require 'wsdl/soap/fault'
require 'wsdl/soap/address'
require 'wsdl/soap/complexType'


module WSDL
module SOAP


HeaderFaultName = XSD::QName.new(SOAPBindingNamespace, 'headerfault')

LocationAttrName = XSD::QName.new(nil, 'location')
StyleAttrName = XSD::QName.new(nil, 'style')
TransportAttrName = XSD::QName.new(nil, 'transport')
UseAttrName = XSD::QName.new(nil, 'use')
PartsAttrName = XSD::QName.new(nil, 'parts')
PartAttrName = XSD::QName.new(nil, 'part')
NameAttrName = XSD::QName.new(nil, 'name')
MessageAttrName = XSD::QName.new(nil, 'message')
EncodingStyleAttrName = XSD::QName.new(nil, 'encodingStyle')
NamespaceAttrName = XSD::QName.new(nil, 'namespace')
SOAPActionAttrName = XSD::QName.new(nil, 'soapAction')


end
end
