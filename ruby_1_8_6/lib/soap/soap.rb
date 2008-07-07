# soap/soap.rb: SOAP4R - Base definitions.
# Copyright (C) 2000-2004  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/qname'
require 'xsd/charset'


module SOAP


VERSION = Version = '1.5.5'
PropertyName = 'soap/property'

EnvelopeNamespace = 'http://schemas.xmlsoap.org/soap/envelope/'
EncodingNamespace = 'http://schemas.xmlsoap.org/soap/encoding/'
LiteralNamespace = 'http://xml.apache.org/xml-soap/literalxml'

NextActor = 'http://schemas.xmlsoap.org/soap/actor/next'

EleEnvelope = 'Envelope'
EleHeader = 'Header'
EleBody = 'Body'
EleFault = 'Fault'
EleFaultString = 'faultstring'
EleFaultActor = 'faultactor'
EleFaultCode = 'faultcode'
EleFaultDetail = 'detail'

AttrMustUnderstand = 'mustUnderstand'
AttrEncodingStyle = 'encodingStyle'
AttrActor = 'actor'
AttrRoot = 'root'
AttrArrayType = 'arrayType'
AttrOffset = 'offset'
AttrPosition = 'position'
ValueArray = 'Array'

EleEnvelopeName = XSD::QName.new(EnvelopeNamespace, EleEnvelope).freeze
EleHeaderName = XSD::QName.new(EnvelopeNamespace, EleHeader).freeze
EleBodyName = XSD::QName.new(EnvelopeNamespace, EleBody).freeze
EleFaultName = XSD::QName.new(EnvelopeNamespace, EleFault).freeze
EleFaultStringName = XSD::QName.new(nil, EleFaultString).freeze
EleFaultActorName = XSD::QName.new(nil, EleFaultActor).freeze
EleFaultCodeName = XSD::QName.new(nil, EleFaultCode).freeze
EleFaultDetailName = XSD::QName.new(nil, EleFaultDetail).freeze
AttrMustUnderstandName = XSD::QName.new(EnvelopeNamespace, AttrMustUnderstand).freeze
AttrEncodingStyleName = XSD::QName.new(EnvelopeNamespace, AttrEncodingStyle).freeze
AttrRootName = XSD::QName.new(EncodingNamespace, AttrRoot).freeze
AttrArrayTypeName = XSD::QName.new(EncodingNamespace, AttrArrayType).freeze
AttrOffsetName = XSD::QName.new(EncodingNamespace, AttrOffset).freeze
AttrPositionName = XSD::QName.new(EncodingNamespace, AttrPosition).freeze
ValueArrayName = XSD::QName.new(EncodingNamespace, ValueArray).freeze

Base64Literal = 'base64'

SOAPNamespaceTag = 'env'
XSDNamespaceTag = 'xsd'
XSINamespaceTag = 'xsi'

MediaType = 'text/xml'

class Error < StandardError; end

class StreamError < Error; end
class HTTPStreamError < StreamError; end
class PostUnavailableError < HTTPStreamError; end
class MPostUnavailableError < HTTPStreamError; end

class ArrayIndexOutOfBoundsError < Error; end
class ArrayStoreError < Error; end

class RPCRoutingError < Error; end
class EmptyResponseError < Error; end
class ResponseFormatError < Error; end

class UnhandledMustUnderstandHeaderError < Error; end

class FaultError < Error
  attr_reader :faultcode
  attr_reader :faultstring
  attr_reader :faultactor
  attr_accessor :detail

  def initialize(fault)
    @faultcode = fault.faultcode
    @faultstring = fault.faultstring
    @faultactor = fault.faultactor
    @detail = fault.detail
    super(self.to_s)
  end

  def to_s
    str = nil
    if @faultstring and @faultstring.respond_to?('data')
      str = @faultstring.data
    end
    str || '(No faultstring)'
  end
end


module Env
  def self.getenv(name)
    ENV[name.downcase] || ENV[name.upcase]
  end

  use_proxy = getenv('soap_use_proxy') == 'on'
  HTTP_PROXY = use_proxy ? getenv('http_proxy') : nil
  NO_PROXY = use_proxy ? getenv('no_proxy') : nil
end


end


unless Object.respond_to?(:instance_variable_get)
  class Object
    def instance_variable_get(ivarname)
      instance_eval(ivarname)
    end

    def instance_variable_set(ivarname, value)
      instance_eval("#{ivarname} = value")
    end
  end
end


unless Kernel.respond_to?(:warn)
  module Kernel
    def warn(msg)
      STDERR.puts(msg + "\n") unless $VERBOSE.nil?
    end
  end
end
