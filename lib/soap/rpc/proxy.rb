# SOAP4R - RPC Proxy library.
# Copyright (C) 2000, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/processor'
require 'soap/mapping'
require 'soap/rpc/rpc'
require 'soap/rpc/element'
require 'soap/streamHandler'


module SOAP
module RPC


class Proxy
  include SOAP

public

  attr_accessor :soapaction
  attr_accessor :mandatorycharset
  attr_accessor :allow_unqualified_element
  attr_accessor :default_encodingstyle
  attr_reader :method

  def initialize(streamhandler, soapaction = nil)
    @streamhandler = streamhandler
    @soapaction = soapaction
    @method = {}
    @mandatorycharset = nil
    @allow_unqualified_element = false
    @default_encodingstyle = nil
  end

  class Request
    include RPC

  public

    attr_reader :method
    attr_reader :namespace
    attr_reader :name

    def initialize(model, values)
      @method = model.dup
      @namespace = @method.elename.namespace
      @name = @method.elename.name

      params = {}
    
      if ((values.size == 1) and (values[0].is_a?(Hash)))
        params = values[0]
      else
        i = 0
        @method.each_param_name(SOAPMethod::IN, SOAPMethod::INOUT) do |name|
          params[name] = values[i] || SOAPNil.new
          i += 1
        end
      end
      @method.set_param(params)
    end
  end

  def add_method(qname, soapaction, name, param_def)
    @method[name] = SOAPMethodRequest.new(qname, param_def, soapaction)
  end

  def create_request(name, *values)
    if (@method.key?(name))
      method = @method[name]
      method.encodingstyle = @default_encodingstyle if @default_encodingstyle
    else
      raise SOAP::RPC::MethodDefinitionError.new(
	"Method: #{ name } not defined.")
    end

    Request.new(method, values)
  end

  def invoke(req_header, req_body, soapaction = nil)
    if req_header and !req_header.is_a?(SOAPHeader)
      req_header = create_header(req_header)
    end
    if !req_body.is_a?(SOAPBody)
      req_body = SOAPBody.new(req_body)
    end
    opt = create_options
    send_string = Processor.marshal(req_header, req_body, opt)
    data = @streamhandler.send(send_string, soapaction)
    if data.receive_string.empty?
      return nil, nil
    end
    opt = create_options
    opt[:charset] = @mandatorycharset ||
      StreamHandler.parse_media_type(data.receive_contenttype)
    res_header, res_body = Processor.unmarshal(data.receive_string, opt)
    return res_header, res_body
  end

  def call(headers, name, *values)
    req = create_request(name, *values)
    return invoke(headers, req.method, req.method.soapaction || @soapaction)
  end

  def check_fault(body)
    if body.fault
      raise SOAP::FaultError.new(body.fault)
    end
  end

private

  def create_header(headers)
    header = SOAPHeader.new()
    headers.each do |content, mustunderstand, encodingstyle|
      header.add(SOAPHeaderItem.new(content, mustunderstand, encodingstyle))
    end
    header
  end

  def create_options
    opt = {}
    opt[:default_encodingstyle] = @default_encodingstyle
    if @allow_unqualified_element
      opt[:allow_unqualified_element] = true
    end
    opt
  end
end


end
end
