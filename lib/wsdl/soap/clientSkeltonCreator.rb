# WSDL4R - Creating client skelton code from WSDL.
# Copyright (C) 2002, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'wsdl/info'
require 'wsdl/soap/classDefCreatorSupport'


module WSDL
module SOAP


class ClientSkeltonCreator
  include ClassDefCreatorSupport

  attr_reader :definitions

  def initialize(definitions)
    @definitions = definitions
  end

  def dump(service_name)
    result = ""
    @definitions.service(service_name).ports.each do |port|
      result << dump_porttype(port.porttype.name)
      result << "\n"
    end
    result
  end

private

  def dump_porttype(name)
    drv_name = create_class_name(name)

    result = ""
    result << <<__EOD__
endpoint_url = ARGV.shift
obj = #{ drv_name }.new(endpoint_url)

# Uncomment the below line to see SOAP wiredumps.
# obj.wiredump_dev = STDERR

__EOD__
    @definitions.porttype(name).operations.each do |operation|
      result << dump_method_signature(operation)
      result << dump_input_init(operation.input) << "\n"
      result << dump_operation(operation) << "\n\n"
    end
    result
  end

  def dump_operation(operation)
    name = operation.name
    input = operation.input
    "puts obj.#{ safemethodname(name.name) }#{ dump_inputparam(input) }"
  end

  def dump_input_init(input)
    result = input.find_message.parts.collect { |part|
      safevarname(part.name)
    }.join(" = ")
    if result.empty?
      ""
    else
      result << " = nil"
    end
    result
  end
end


end
end
