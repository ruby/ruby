=begin
WSDL4R - WSDL additional definitions for SOAP.
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


require 'wsdl/info'
require 'xsd/namedelements'
require 'soap/mapping'


module WSDL


class Definitions < Info
  def soap_rpc_complextypes(binding)
    types = rpc_operation_complextypes(binding)
    types << array_complextype
    types << fault_complextype
    types << exception_complextype
    types
  end

private

  def rpc_operation_complextypes(binding)
    types = XSD::NamedElements.new
    binding.operations.each do |op_bind|
      if op_bind_rpc?(op_bind)
	operation = op_bind.find_operation
	if op_bind.input
	  type = XMLSchema::ComplexType.new(operation_input_name(operation))
	  message = messages[operation.input.message]
	  type.sequence_elements = elements_from_message(message)
	  types << type
	end
	if op_bind.output
	  type = XMLSchema::ComplexType.new(operation_output_name(operation))
	  message = messages[operation.output.message]
	  type.sequence_elements = elements_from_message(message)
	  types << type
	end
      end
    end
    types
  end

  def operation_input_name(operation)
    operation.input.name || operation.name
  end

  def operation_output_name(operation)
    operation.output.name ||
      XSD::QName.new(operation.name.namespace, operation.name.name + "Response")
  end

  def op_bind_rpc?(op_bind)
    op_bind.soapoperation and op_bind.soapoperation.operation_style == :rpc
  end

  def elements_from_message(message)
    message.parts.collect { |part|
      qname = XSD::QName.new(nil, part.name)
      XMLSchema::Element.new(qname, part.type)
    }
  end

  def array_complextype
    type = XMLSchema::ComplexType.new(::SOAP::ValueArrayName)
    type.complexcontent = XMLSchema::ComplexContent.new
    type.complexcontent.base = ::SOAP::ValueArrayName
    attr = XMLSchema::Attribute.new
    attr.ref = ::SOAP::AttrArrayTypeName
    anytype = XSD::AnyTypeName.dup
    anytype.name += '[]'
    attr.arytype = anytype
    type.complexcontent.attributes << attr
    type
  end

=begin
<xs:complexType name="Fault" final="extension">
  <xs:sequence>
    <xs:element name="faultcode" type="xs:QName" /> 
    <xs:element name="faultstring" type="xs:string" /> 
    <xs:element name="faultactor" type="xs:anyURI" minOccurs="0" /> 
    <xs:element name="detail" type="tns:detail" minOccurs="0" /> 
  </xs:sequence>
</xs:complexType>
=end
  def fault_complextype
    type = XMLSchema::ComplexType.new(::SOAP::EleFaultName)
    faultcode = XMLSchema::Element.new(::SOAP::EleFaultCodeName, XSD::XSDQName::Type)
    faultstring = XMLSchema::Element.new(::SOAP::EleFaultStringName, XSD::XSDString::Type)
    faultactor = XMLSchema::Element.new(::SOAP::EleFaultActorName, XSD::XSDAnyURI::Type)
    faultactor.minoccurs = 0
    detail = XMLSchema::Element.new(::SOAP::EleFaultDetailName, XSD::AnyTypeName)
    detail.minoccurs = 0
    type.all_elements = [faultcode, faultstring, faultactor, detail]
    type.final = 'extension'
    type
  end

  def exception_complextype
    type = XMLSchema::ComplexType.new(XSD::QName.new(
	::SOAP::Mapping::RubyCustomTypeNamespace, 'SOAPException'))
    excn_name = XMLSchema::Element.new(XSD::QName.new(nil, 'excn_type_name'), XSD::XSDString::Type)
    cause = XMLSchema::Element.new(XSD::QName.new(nil, 'cause'), XSD::AnyTypeName)
    backtrace = XMLSchema::Element.new(XSD::QName.new(nil, 'backtrace'), ::SOAP::ValueArrayName)
    message = XMLSchema::Element.new(XSD::QName.new(nil, 'message'), XSD::XSDString::Type)
    type.all_elements = [excn_name, cause, backtrace, message]
    type
  end
end


end
