# WSDL4R - Creating driver code from WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/mappingRegistryCreator'
require 'wsdl/soap/methodDefCreator'
require 'wsdl/soap/classDefCreatorSupport'
require 'xsd/codegen'


module WSDL
module SOAP


class DriverCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions)
    @definitions = definitions
  end

  def dump(porttype = nil)
    if porttype.nil?
      result = ""
      @definitions.porttypes.each do |type|
	result << dump_porttype(type.name)
	result << "\n"
      end
    else
      result = dump_porttype(porttype)
    end
    result
  end

private

  def dump_porttype(name)
    class_name = create_class_name(name)
    methoddef, types = MethodDefCreator.new(@definitions).dump(name)
    mr_creator = MappingRegistryCreator.new(@definitions)
    binding = @definitions.bindings.find { |item| item.type == name }
    addresses = @definitions.porttype(name).locations

    c = ::XSD::CodeGen::ClassDef.new(class_name, "::SOAP::RPC::Driver")
    c.def_require("soap/rpc/driver")
    c.def_const("MappingRegistry", "::SOAP::Mapping::Registry.new")
    c.def_const("DefaultEndpointUrl", addresses[0].dump)
    c.def_code(mr_creator.dump(types))
    c.def_code <<-EOD
Methods = [
#{ methoddef.gsub(/^/, "  ") }
]
    EOD
    c.def_method("initialize", "endpoint_url = nil") do
      <<-EOD
        endpoint_url ||= DefaultEndpointUrl
        super(endpoint_url, nil)
        self.mapping_registry = MappingRegistry
        init_methods
      EOD
    end
    c.def_privatemethod("init_methods") do
      <<-EOD
        Methods.each do |name_as, name, params, soapaction, namespace, style|
          qname = ::XSD::QName.new(namespace, name_as)
          if style == :document
            @proxy.add_document_method(qname, soapaction, name, params)
            add_document_method_interface(name, name_as)
          else
            @proxy.add_rpc_method(qname, soapaction, name, params)
            add_rpc_method_interface(name, params)
          end
        end
      EOD
    end
    c.dump
  end
end


end
end
