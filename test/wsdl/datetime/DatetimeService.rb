#!/usr/bin/env ruby
require 'datetimeServant.rb'

require 'soap/rpc/standaloneServer'

class DatetimePortType
  MappingRegistry = SOAP::Mapping::Registry.new

  # No mapping definition

  Methods = [
    ["now", "now", [
      ["in", "now",
       [SOAP::SOAPDateTime]],
      ["retval", "now",
       [SOAP::SOAPDateTime]]], "", "urn:jp.gr.jin.rrr.example.datetime"]
  ]
end

class DatetimePortTypeApp < SOAP::RPC::StandaloneServer
  def initialize(*arg)
    super

    servant = DatetimePortType.new
    DatetimePortType::Methods.each do |name_as, name, params, soapaction, namespace|
      qname = XSD::QName.new(namespace, name_as)
      @soaplet.app_scope_router.add_method(servant, qname, soapaction,
	name, params)
    end

    self.mapping_registry = DatetimePortType::MappingRegistry
  end
end

# Change listen port.
if $0 == __FILE__
  DatetimePortTypeApp.new('app', nil, '0.0.0.0', 10080).start
end
