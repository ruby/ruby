=begin
SOAP4R - Base definitions.
Copyright (C) 2000, 2001, 2002, 2003  NAKAMURA, Hiroshi.

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


require 'xsd/qname'
require 'xsd/charset'


module SOAP


Version = '1.5.1'

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

EleEnvelopeName = XSD::QName.new(EnvelopeNamespace, EleEnvelope)
EleHeaderName = XSD::QName.new(EnvelopeNamespace, EleHeader)
EleBodyName = XSD::QName.new(EnvelopeNamespace, EleBody)
EleFaultName = XSD::QName.new(EnvelopeNamespace, EleFault)
EleFaultStringName = XSD::QName.new(nil, EleFaultString)
EleFaultActorName = XSD::QName.new(nil, EleFaultActor)
EleFaultCodeName = XSD::QName.new(nil, EleFaultCode)
EleFaultDetailName = XSD::QName.new(nil, EleFaultDetail)
AttrEncodingStyleName = XSD::QName.new(EnvelopeNamespace, AttrEncodingStyle)
AttrRootName = XSD::QName.new(EncodingNamespace, AttrRoot)
AttrArrayTypeName = XSD::QName.new(EncodingNamespace, AttrArrayType)
AttrOffsetName = XSD::QName.new(EncodingNamespace, AttrOffset)
AttrPositionName = XSD::QName.new(EncodingNamespace, AttrPosition)
ValueArrayName = XSD::QName.new(EncodingNamespace, ValueArray)

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
    if @faultstring && @faultstring.respond_to?('data')
      str = @faultstring.data
    end
    str || '(No faultstring)'
  end
end


end
