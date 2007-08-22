#!/usr/bin/env ruby
require 'datetimeServant.rb'

require 'soap/rpc/standaloneServer'
require 'soap/mapping/registry'

class DatetimePortType
  MappingRegistry = ::SOAP::Mapping::Registry.new

  Methods = [
    ["now", "now",
      [
        ["in", "now", [::SOAP::SOAPDateTime]],
        ["retval", "now", [::SOAP::SOAPDateTime]]
      ],
      "", "urn:jp.gr.jin.rrr.example.datetime", :rpc
    ]
  ]
end

class DatetimePortTypeApp < ::SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super(*arg)
    servant = DatetimePortType.new
    DatetimePortType::Methods.each do |name_as, name, param_def, soapaction, namespace, style|
      if style == :document
        @router.add_document_operation(servant, soapaction, name, param_def)
      else
        qname = XSD::QName.new(namespace, name_as)
        @router.add_rpc_operation(servant, qname, soapaction, name, param_def)
      end
    end
    self.mapping_registry = DatetimePortType::MappingRegistry
  end
end

if $0 == __FILE__
  # Change listen port.
  server = DatetimePortTypeApp.new('app', nil, '0.0.0.0', 10080)
  trap(:INT) do
    server.shutdown
  end
  server.start
end
