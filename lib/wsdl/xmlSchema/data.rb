=begin
WSDL4R - XMLSchema data definitions.
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


require 'wsdl/xmlSchema/schema'
require 'wsdl/xmlSchema/import'
require 'wsdl/xmlSchema/complexType'
require 'wsdl/xmlSchema/complexContent'
require 'wsdl/xmlSchema/any'
require 'wsdl/xmlSchema/element'
require 'wsdl/xmlSchema/all'
require 'wsdl/xmlSchema/choice'
require 'wsdl/xmlSchema/sequence'
require 'wsdl/xmlSchema/attribute'
require 'wsdl/xmlSchema/unique'


module WSDL
module XMLSchema


AllName = XSD::QName.new(XSD::Namespace, 'all')
AnyName = XSD::QName.new(XSD::Namespace, 'any')
ArrayTypeAttrName = XSD::QName.new(XSD::Namespace, 'arrayType')
AttributeName = XSD::QName.new(XSD::Namespace, 'attribute')
ChoiceName = XSD::QName.new(XSD::Namespace, 'choice')
ComplexContentName = XSD::QName.new(XSD::Namespace, 'complexContent')
ComplexTypeName = XSD::QName.new(XSD::Namespace, 'complexType')
ElementName = XSD::QName.new(XSD::Namespace, 'element')
ExtensionName = XSD::QName.new(XSD::Namespace, 'extension')
ImportName = XSD::QName.new(XSD::Namespace, 'import')
RestrictionName = XSD::QName.new(XSD::Namespace, 'restriction')
SequenceName = XSD::QName.new(XSD::Namespace, 'sequence')
SchemaName = XSD::QName.new(XSD::Namespace, 'schema')
SimpleTypeName = XSD::QName.new(XSD::Namespace, 'simpleType')
UniqueName = XSD::QName.new(XSD::Namespace, 'unique')

AttributeFormDefaultAttrName = XSD::QName.new(nil, 'attributeFormDefault')
BaseAttrName = XSD::QName.new(nil, 'base')
DefaultAttrName = XSD::QName.new(nil, 'default')
ElementFormDefaultAttrName = XSD::QName.new(nil, 'elementFormDefault')
FinalAttrName = XSD::QName.new(nil, 'final')
FixedAttrName = XSD::QName.new(nil, 'fixed')
FormAttrName = XSD::QName.new(nil, 'form')
IdAttrName = XSD::QName.new(nil, 'id')
MaxOccursAttrName = XSD::QName.new(nil, 'maxOccurs')
MinOccursAttrName = XSD::QName.new(nil, 'minOccurs')
MixedAttrName = XSD::QName.new(nil, 'mixed')
NameAttrName = XSD::QName.new(nil, 'name')
NamespaceAttrName = XSD::QName.new(nil, 'namespace')
NillableAttrName = XSD::QName.new(nil, 'nillable')
RefAttrName = XSD::QName.new(nil, 'ref')
SchemaLocationAttrName = XSD::QName.new(nil, 'schemaLocation')
TargetNamespaceAttrName = XSD::QName.new(nil, 'targetNamespace')
TypeAttrName = XSD::QName.new(nil, 'type')
UseAttrName = XSD::QName.new(nil, 'use')


end
end
