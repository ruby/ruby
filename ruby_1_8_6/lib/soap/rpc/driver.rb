# SOAP4R - SOAP RPC driver
# Copyright (C) 2000, 2001, 2003-2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'soap/soap'
require 'soap/mapping'
require 'soap/mapping/wsdlliteralregistry'
require 'soap/rpc/rpc'
require 'soap/rpc/proxy'
require 'soap/rpc/element'
require 'soap/streamHandler'
require 'soap/property'
require 'soap/header/handlerset'


module SOAP
module RPC


class Driver
  class << self
    if RUBY_VERSION >= "1.7.0"
      def __attr_proxy(symbol, assignable = false)
        name = symbol.to_s
        define_method(name) {
          @proxy.__send__(name)
        }
        if assignable
          aname = name + '='
          define_method(aname) { |rhs|
            @proxy.__send__(aname, rhs)
          }
        end
      end
    else
      def __attr_proxy(symbol, assignable = false)
        name = symbol.to_s
        module_eval <<-EOS
          def #{name}
            @proxy.#{name}
          end
        EOS
        if assignable
          module_eval <<-EOS
            def #{name}=(value)
              @proxy.#{name} = value
            end
          EOS
        end
      end
    end
  end

  __attr_proxy :endpoint_url, true
  __attr_proxy :mapping_registry, true
  __attr_proxy :default_encodingstyle, true
  __attr_proxy :generate_explicit_type, true
  __attr_proxy :allow_unqualified_element, true
  __attr_proxy :headerhandler
  __attr_proxy :streamhandler
  __attr_proxy :test_loopback_response
  __attr_proxy :reset_stream

  attr_reader :proxy
  attr_reader :options
  attr_accessor :soapaction

  def inspect
    "#<#{self.class}:#{@proxy.inspect}>"
  end

  def httpproxy
    options["protocol.http.proxy"]
  end

  def httpproxy=(httpproxy)
    options["protocol.http.proxy"] = httpproxy
  end

  def wiredump_dev
    options["protocol.http.wiredump_dev"]
  end

  def wiredump_dev=(wiredump_dev)
    options["protocol.http.wiredump_dev"] = wiredump_dev
  end

  def mandatorycharset
    options["protocol.mandatorycharset"]
  end

  def mandatorycharset=(mandatorycharset)
    options["protocol.mandatorycharset"] = mandatorycharset
  end

  def wiredump_file_base
    options["protocol.wiredump_file_base"]
  end

  def wiredump_file_base=(wiredump_file_base)
    options["protocol.wiredump_file_base"] = wiredump_file_base
  end

  def initialize(endpoint_url, namespace = nil, soapaction = nil)
    @namespace = namespace
    @soapaction = soapaction
    @options = setup_options
    @wiredump_file_base = nil
    @proxy = Proxy.new(endpoint_url, @soapaction, @options)
  end

  def loadproperty(propertyname)
    unless options.loadproperty(propertyname)
      raise LoadError.new("No such property to load -- #{propertyname}")
    end
  end

  def add_rpc_method(name, *params)
    add_rpc_method_with_soapaction_as(name, name, @soapaction, *params)
  end

  def add_rpc_method_as(name, name_as, *params)
    add_rpc_method_with_soapaction_as(name, name_as, @soapaction, *params)
  end

  def add_rpc_method_with_soapaction(name, soapaction, *params)
    add_rpc_method_with_soapaction_as(name, name, soapaction, *params)
  end

  def add_rpc_method_with_soapaction_as(name, name_as, soapaction, *params)
    param_def = SOAPMethod.create_rpc_param_def(params)
    qname = XSD::QName.new(@namespace, name_as)
    @proxy.add_rpc_method(qname, soapaction, name, param_def)
    add_rpc_method_interface(name, param_def)
  end

  # add_method is for shortcut of typical rpc/encoded method definition.
  alias add_method add_rpc_method
  alias add_method_as add_rpc_method_as
  alias add_method_with_soapaction add_rpc_method_with_soapaction
  alias add_method_with_soapaction_as add_rpc_method_with_soapaction_as

  def add_document_method(name, soapaction, req_qname, res_qname)
    param_def = SOAPMethod.create_doc_param_def(req_qname, res_qname)
    @proxy.add_document_method(soapaction, name, param_def)
    add_document_method_interface(name, param_def)
  end

  def add_rpc_operation(qname, soapaction, name, param_def, opt = {})
    @proxy.add_rpc_operation(qname, soapaction, name, param_def, opt)
    add_rpc_method_interface(name, param_def)
  end

  def add_document_operation(soapaction, name, param_def, opt = {})
    @proxy.add_document_operation(soapaction, name, param_def, opt)
    add_document_method_interface(name, param_def)
  end

  def invoke(headers, body)
    if headers and !headers.is_a?(SOAPHeader)
      headers = create_header(headers)
    end
    set_wiredump_file_base(body.elename.name)
    env = @proxy.invoke(headers, body)
    if env.nil?
      return nil, nil
    else
      return env.header, env.body
    end
  end

  def call(name, *params)
    set_wiredump_file_base(name)
    @proxy.call(name, *params)
  end

private

  def set_wiredump_file_base(name)
    if @wiredump_file_base
      @proxy.set_wiredump_file_base("#{@wiredump_file_base}_#{name}")
    end
  end

  def create_header(headers)
    header = SOAPHeader.new()
    headers.each do |content, mustunderstand, encodingstyle|
      header.add(SOAPHeaderItem.new(content, mustunderstand, encodingstyle))
    end
    header
  end

  def setup_options
    if opt = Property.loadproperty(::SOAP::PropertyName)
      opt = opt["client"]
    end
    opt ||= Property.new
    opt.add_hook("protocol.mandatorycharset") do |key, value|
      @proxy.mandatorycharset = value
    end
    opt.add_hook("protocol.wiredump_file_base") do |key, value|
      @wiredump_file_base = value
    end
    opt["protocol.http.charset"] ||= XSD::Charset.xml_encoding_label
    opt["protocol.http.proxy"] ||= Env::HTTP_PROXY
    opt["protocol.http.no_proxy"] ||= Env::NO_PROXY
    opt
  end

  def add_rpc_method_interface(name, param_def)
    param_count = RPC::SOAPMethod.param_count(param_def,
      RPC::SOAPMethod::IN, RPC::SOAPMethod::INOUT)
    add_method_interface(name, param_count)
  end

  def add_document_method_interface(name, param_def)
    param_count = RPC::SOAPMethod.param_count(param_def, RPC::SOAPMethod::IN)
    add_method_interface(name, param_count)
  end

  if RUBY_VERSION > "1.7.0"
    def add_method_interface(name, param_count)
      ::SOAP::Mapping.define_singleton_method(self, name) do |*arg|
        unless arg.size == param_count
          raise ArgumentError.new(
          "wrong number of arguments (#{arg.size} for #{param_count})")
        end
        call(name, *arg)
      end
      self.method(name)
    end
  else
    def add_method_interface(name, param_count)
      instance_eval <<-EOS
        def #{name}(*arg)
          unless arg.size == #{param_count}
            raise ArgumentError.new(
              "wrong number of arguments (\#{arg.size} for #{param_count})")
          end
          call(#{name.dump}, *arg)
        end
      EOS
      self.method(name)
    end
  end
end


end
end
