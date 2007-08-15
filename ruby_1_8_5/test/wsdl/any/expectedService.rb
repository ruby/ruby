#!/usr/bin/env ruby
require 'echoServant.rb'

require 'soap/rpc/standaloneServer'
require 'soap/mapping/registry'

class Echo_port_type
  MappingRegistry = ::SOAP::Mapping::Registry.new

  MappingRegistry.set(
    FooBar,
    ::SOAP::SOAPStruct,
    ::SOAP::Mapping::Registry::TypedStructFactory,
    { :type => XSD::QName.new("urn:example.com:echo-type", "foo.bar") }
  )

  Methods = [
    [ XSD::QName.new("urn:example.com:echo", "echo"),
      "urn:example.com:echo",
      "echo",
      [ ["in", "echoitem", ["FooBar", "urn:example.com:echo-type", "foo.bar"]],
        ["retval", "echoitem", ["FooBar", "urn:example.com:echo-type", "foo.bar"]] ],
      { :request_style =>  :rpc, :request_use =>  :encoded,
        :response_style => :rpc, :response_use => :encoded }
    ]
  ]
end

class Echo_port_typeApp < ::SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super(*arg)
    servant = Echo_port_type.new
    Echo_port_type::Methods.each do |definitions|
      opt = definitions.last
      if opt[:request_style] == :document
        @router.add_document_operation(servant, *definitions)
      else
        @router.add_rpc_operation(servant, *definitions)
      end
    end
    self.mapping_registry = Echo_port_type::MappingRegistry
  end
end

if $0 == __FILE__
  # Change listen port.
  server = Echo_port_typeApp.new('app', nil, '0.0.0.0', 10080)
  trap(:INT) do
    server.shutdown
  end
  server.start
end
