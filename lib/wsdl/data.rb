=begin
WSDL4R - WSDL data definitions.
Copyright (C) 2002, 2003  NAKAMURA, Hiroshi.

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
