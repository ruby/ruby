# WSDL4R - Creating standalone server stub code from WSDL.
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


class StandaloneServerStubCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions)
    @definitions = definitions
  end

  def dump(service_name)
    warn("- Standalone stub can have only 1 port for now.  So creating stub for the first port and rests are ignored.")
    warn("- Standalone server stub ignores port location defined in WSDL.  Location is http://localhost:10080/ by default.  Generated client from WSDL must be configured to point this endpoint manually.")
    port = @definitions.service(service_name).ports[0]
    dump_porttype(port.porttype.name)
  end

private

  def dump_porttype(name)
    class_name = create_class_name(name)
    methoddef, types = MethodDefCreator.new(@definitions).dump(name)
    mr_creator = MappingRegistryCreator.new(@definitions)

    c1 = XSD::CodeGen::ClassDef.new(class_name)
    c1.def_require("soap/rpc/standaloneServer")
    c1.def_require("soap/mapping/registry")
    c1.def_const("MappingRegistry", "::SOAP::Mapping::Registry.new")
    c1.def_code(mr_creator.dump(types))
    c1.def_code <<-EOD
Methods = [
#{methoddef.gsub(/^/, "  ")}
]
    EOD
    c2 = XSD::CodeGen::ClassDef.new(class_name + "App",
      "::SOAP::RPC::StandaloneServer")
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
      EOD
    end
    c1.dump + "\n" + c2.dump + format(<<-EOD)

      if $0 == __FILE__
        # Change listen port.
        server = #{class_name}App.new('app', nil, '0.0.0.0', 10080)
        trap(:INT) do
          server.shutdown
        end
        server.start
      end
    EOD
  end
end


end
end
