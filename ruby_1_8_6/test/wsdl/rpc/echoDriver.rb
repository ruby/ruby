require 'echo.rb'

require 'soap/rpc/driver'

class Echo_port_type < ::SOAP::RPC::Driver
  DefaultEndpointUrl = "http://localhost:10080"
  MappingRegistry = ::SOAP::Mapping::Registry.new

  MappingRegistry.set(
    Person,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("urn:rpc-type", "person") }
  )

  Methods = [
    ["echo", "echo",
      [
        ["in", "arg1", [::SOAP::SOAPStruct, "urn:rpc-type", "person"]],
        ["in", "arg2", [::SOAP::SOAPStruct, "urn:rpc-type", "person"]],
        ["retval", "return", [::SOAP::SOAPStruct, "urn:rpc-type", "person"]]
      ],
      "", "urn:rpc", :rpc
    ]
  ]

  def initialize(endpoint_url = nil)
    endpoint_url ||= DefaultEndpointUrl
    super(endpoint_url, nil)
    self.mapping_registry = MappingRegistry
    init_methods
  end

private

  def init_methods
    Methods.each do |name_as, name, params, soapaction, namespace, style|
      qname = XSD::QName.new(namespace, name_as)
      if style == :document
        @proxy.add_document_method(soapaction, name, params)
        add_document_method_interface(name, params)
      else
        @proxy.add_rpc_method(qname, soapaction, name, params)
        add_rpc_method_interface(name, params)
      end
      if name_as != name and name_as.capitalize == name.capitalize
        sclass = class << self; self; end
        sclass.__send__(:define_method, name_as, proc { |*arg|
          __send__(name, *arg)
        })
      end
    end
  end
end

