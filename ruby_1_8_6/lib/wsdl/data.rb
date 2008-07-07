# WSDL4R - WSDL data definitions.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/qname'
require 'wsdl/documentation'
require 'wsdl/definitions'
require 'wsdl/types'
require 'wsdl/message'
require 'wsdl/part'
require 'wsdl/portType'
require 'wsdl/operation'
require 'wsdl/param'
require 'wsdl/binding'
require 'wsdl/operationBinding'
require 'wsdl/service'
require 'wsdl/port'
require 'wsdl/import'


module WSDL


ArrayTypeAttrName = XSD::QName.new(Namespace, 'arrayType')
BindingName = XSD::QName.new(Namespace, 'binding')
DefinitionsName = XSD::QName.new(Namespace, 'definitions')
DocumentationName = XSD::QName.new(Namespace, 'documentation')
FaultName = XSD::QName.new(Namespace, 'fault')
ImportName = XSD::QName.new(Namespace, 'import')
InputName = XSD::QName.new(Namespace, 'input')
MessageName = XSD::QName.new(Namespace, 'message')
OperationName = XSD::QName.new(Namespace, 'operation')
OutputName = XSD::QName.new(Namespace, 'output')
PartName = XSD::QName.new(Namespace, 'part')
PortName = XSD::QName.new(Namespace, 'port')
PortTypeName = XSD::QName.new(Namespace, 'portType')
ServiceName = XSD::QName.new(Namespace, 'service')
TypesName = XSD::QName.new(Namespace, 'types')

SchemaName = XSD::QName.new(XSD::Namespace, 'schema')

SOAPAddressName = XSD::QName.new(SOAPBindingNamespace, 'address')
SOAPBindingName = XSD::QName.new(SOAPBindingNamespace, 'binding')
SOAPHeaderName = XSD::QName.new(SOAPBindingNamespace, 'header')
SOAPBodyName = XSD::QName.new(SOAPBindingNamespace, 'body')
SOAPFaultName = XSD::QName.new(SOAPBindingNamespace, 'fault')
SOAPOperationName = XSD::QName.new(SOAPBindingNamespace, 'operation')

BindingAttrName = XSD::QName.new(nil, 'binding')
ElementAttrName = XSD::QName.new(nil, 'element')
LocationAttrName = XSD::QName.new(nil, 'location')
MessageAttrName = XSD::QName.new(nil, 'message')
NameAttrName = XSD::QName.new(nil, 'name')
NamespaceAttrName = XSD::QName.new(nil, 'namespace')
ParameterOrderAttrName = XSD::QName.new(nil, 'parameterOrder')
TargetNamespaceAttrName = XSD::QName.new(nil, 'targetNamespace')
TypeAttrName = XSD::QName.new(nil, 'type')


end
