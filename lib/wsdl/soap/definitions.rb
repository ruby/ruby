# WSDL4R - WSDL additional definitions for SOAP.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'xsd/namedelements'
require 'soap/mapping'


module WSDL


class Definitions < Info
  def self.soap_rpc_complextypes
    types = XSD::NamedElements.new
    types << array_complextype
    types << fault_complextype
    types << exception_complextype
    types
  end

  def self.array_complextype
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
  def self.fault_complextype
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

  def self.exception_complextype
    type = XMLSchema::ComplexType.new(XSD::QName.new(
	::SOAP::Mapping::RubyCustomTypeNamespace, 'SOAPException'))
    excn_name = XMLSchema::Element.new(XSD::QName.new(nil, 'excn_type_name'), XSD::XSDString::Type)
    cause = XMLSchema::Element.new(XSD::QName.new(nil, 'cause'), XSD::AnyTypeName)
    backtrace = XMLSchema::Element.new(XSD::QName.new(nil, 'backtrace'), ::SOAP::ValueArrayName)
    message = XMLSchema::Element.new(XSD::QName.new(nil, 'message'), XSD::XSDString::Type)
    type.all_elements = [excn_name, cause, backtrace, message]
    type
  end

  def soap_rpc_complextypes(binding)
    types = rpc_operation_complextypes(binding)
    types + self.class.soap_rpc_complextypes
  end

  def collect_faulttypes
    result = []
    collect_fault_messages.each do |message|
      parts = message(message).parts
      if parts.size != 1
	raise RuntimeError.new("Expecting fault message to have only 1 part.")
      end
      if result.index(parts[0].type).nil?
	result << parts[0].type
      end
    end
    result
  end

private

  def collect_fault_messages
    result = []
    porttypes.each do |porttype|
      porttype.operations.each do |operation|
	operation.fault.each do |fault|
	  if result.index(fault.message).nil?
	    result << fault.message
	  end
	end
      end
    end
    result
  end

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
end


end
