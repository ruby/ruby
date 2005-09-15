# WSDL4R - Creating CGI stub code from WSDL.
# Copyright (C) 2002, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/mappingRegistryCreator'
require 'wsdl/soap/methodDefCreator'
require 'wsdl/soap/classDefCreatorSupport'


module WSDL
module SOAP


class CGIStubCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions)
    @definitions = definitions
  end

  def dump(service_name)
    warn("CGI stub can have only 1 port.  Creating stub for the first port...  Rests are ignored.")
    port = @definitions.service(service_name).ports[0]
    dump_porttype(port.porttype.name)
  end

private

  def dump_porttype(name)
    class_name = create_class_name(name)
    methoddef, types = MethodDefCreator.new(@definitions).dump(name)
    mr_creator = MappingRegistryCreator.new(@definitions)
    c1 = XSD::CodeGen::ClassDef.new(class_name)
    c1.def_require("soap/rpc/cgistub")
    c1.def_require("soap/mapping/registry")
    c1.def_const("MappingRegistry", "::SOAP::Mapping::Registry.new")
    c1.def_code(mr_creator.dump(types))
    c1.def_code <<-EOD
Methods = [
#{methoddef.gsub(/^/, "  ")}
]
    EOD
    c2 = XSD::CodeGen::ClassDef.new(class_name + "App",
      "::SOAP::RPC::CGIStub")
    c2.def_method("initialize", "*arg") do
      <<-EOD
        super(*arg)
        servant = #{class_name}.new
        #{class_name}::Methods.each do |definitions|
          opt = definitions.last
          if opt[:request_style] == :document
            @router.add_document_operation(servant, *definitions)
          else
            @router.add_rpc_operation(servant, *definitions)
          end
        end
        self.mapping_registry = #{class_name}::MappingRegistry
        self.level = Logger::Severity::ERROR
      EOD
    end
    c1.dump + "\n" + c2.dump + format(<<-EOD)
      #{class_name}App.new('app', nil).start
    EOD
  end
end


end
end
