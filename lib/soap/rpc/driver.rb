=begin
SOAP4R - SOAP RPC driver
Copyright (C) 2000, 2001, 2003  NAKAMURA, Hiroshi.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PRATICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 675 Mass
Ave, Cambridge, MA 02139, USA.
=end


require 'soap/soap'
require 'soap/mapping'
require 'soap/rpc/rpc'
require 'soap/rpc/proxy'
require 'soap/rpc/element'
require 'soap/streamHandler'


module SOAP
module RPC


class Driver
public
  class EmptyResponseError < Error; end

  attr_accessor :mapping_registry
  attr_accessor :soapaction
  attr_reader :endpoint_url
  attr_reader :wiredump_dev
  attr_reader :wiredump_file_base
  attr_reader :httpproxy

  def initialize(endpoint_url, namespace, soapaction = nil)
    @endpoint_url = endpoint_url
    @namespace = namespace
    @mapping_registry = nil      # for unmarshal
    @soapaction = soapaction
    @wiredump_dev = nil
    @wiredump_file_base = nil
    @httpproxy = ENV['httpproxy'] || ENV['HTTP_PROXY']
    @handler = HTTPPostStreamHandler.new(@endpoint_url, @httpproxy,
      XSD::Charset.encoding_label)
    @proxy = Proxy.new(@handler, @soapaction)
    @proxy.allow_unqualified_element = true
  end

  def endpoint_url=(endpoint_url)
    @endpoint_url = endpoint_url
    if @handler
      @handler.endpoint_url = @endpoint_url
      @handler.reset
    end
  end

  def wiredump_dev=(dev)
    @wiredump_dev = dev
    if @handler
      @handler.wiredump_dev = @wiredump_dev
      @handler.reset
    end
  end

  def wiredump_file_base=(base)
    @wiredump_file_base = base
  end

  def httpproxy=(httpproxy)
    @httpproxy = httpproxy
    if @handler
      @handler.proxy = @httpproxy
      @handler.reset
    end
  end

  def default_encodingstyle
    @proxy.default_encodingstyle
  end

  def default_encodingstyle=(encodingstyle)
    @proxy.default_encodingstyle = encodingstyle
  end


  ###
  ## Method definition interfaces.
  #
  # params: [[param_def...]] or [paramname, paramname, ...]
  # param_def: See proxy.rb.  Sorry.

  def add_method(name, *params)
    add_method_with_soapaction_as(name, name, @soapaction, *params)
  end

  def add_method_as(name, name_as, *params)
    add_method_with_soapaction_as(name, name_as, @soapaction, *params)
  end

  def add_method_with_soapaction(name, soapaction, *params)
    add_method_with_soapaction_as(name, name, soapaction, *params)
  end

  def add_method_with_soapaction_as(name, name_as, soapaction, *params)
    param_def = if params.size == 1 and params[0].is_a?(Array)
        params[0]
      else
        SOAPMethod.create_param_def(params)
      end
    qname = XSD::QName.new(@namespace, name_as)
    @proxy.add_method(qname, soapaction, name, param_def)
    add_rpc_method_interface(name, param_def)
  end


  ###
  ## Driving interface.
  #
  def invoke(headers, body)
    if @wiredump_file_base
      @handler.wiredump_file_base =
	@wiredump_file_base + '_' << body.elename.name
    end
    @proxy.invoke(headers, body)
  end

  def call(name, *params)
    # Convert parameters: params array => SOAPArray => members array
    params = Mapping.obj2soap(params, @mapping_registry).to_a
    if @wiredump_file_base
      @handler.wiredump_file_base = @wiredump_file_base + '_' << name
    end

    # Then, call @proxy.call like the following.
    header, body = @proxy.call(nil, name, *params)
    unless body
      raise EmptyResponseError.new("Empty response.")
    end

    begin
      @proxy.check_fault(body)
    rescue SOAP::FaultError => e
      Mapping.fault2exception(e)
    end

    ret = body.response ? Mapping.soap2obj(body.response, @mapping_registry) : nil
    if body.outparams
      outparams = body.outparams.collect { |outparam| Mapping.soap2obj(outparam) }
      return [ret].concat(outparams)
    else
      return ret
    end
  end

  def reset_stream
    @handler.reset
  end

private

  def add_rpc_method_interface(name, param_def)
    param_names = []
    i = 0
    @proxy.method[name].each_param_name(RPC::SOAPMethod::IN,
	RPC::SOAPMethod::INOUT) do |param_name|
      i += 1
      param_names << "arg#{ i }"
    end

    callparam = (param_names.collect { |pname| ", " + pname }).join
    self.instance_eval <<-EOS
      def #{ name }(#{ param_names.join(", ") })
        call("#{ name }"#{ callparam })
      end
    EOS
  end
end


end
end
