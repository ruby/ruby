# SOAP4R - SOAP XML Instance Parser library.
# Copyright (C) 2001, 2003  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


require 'xsd/ns'
require 'xsd/xmlparser'
require 'soap/soap'
require 'soap/baseData'
require 'soap/encodingstyle/handler'


module SOAP


class Parser
  include SOAP

  class ParseError < Error; end
  class FormatDecodeError < ParseError; end
  class UnexpectedElementError < ParseError; end

private

  class ParseFrame
    attr_reader :node
    attr_reader :name
    attr_reader :ns, :encodingstyle

    class NodeContainer
      def initialize(node)
	@node = node
      end

      def node
	@node
      end

      def replace_node(node)
	@node = node
      end
    end

  public

    def initialize(ns, name, node, encodingstyle)
      @ns = ns
      @name = name
      self.node = node
      @encodingstyle = encodingstyle
    end

    def node=(node)
      @node = NodeContainer.new(node)
    end
  end

public

  attr_accessor :default_encodingstyle
  attr_accessor :decode_typemap
  attr_accessor :allow_unqualified_element

  def initialize(opt = {})
    @opt = opt
    @parser = XSD::XMLParser.create_parser(self, opt)
    @parsestack = nil
    @lastnode = nil
    @handlers = {}
    @default_encodingstyle = opt[:default_encodingstyle] || EncodingNamespace
    @decode_typemap = opt[:decode_typemap] || nil
    @allow_unqualified_element = opt[:allow_unqualified_element] || false
  end

  def charset
    @parser.charset
  end

  def parse(string_or_readable)
    @parsestack = []
    @lastnode = nil

    @handlers.each do |uri, handler|
      handler.decode_prologue
    end

    @parser.do_parse(string_or_readable)

    unless @parsestack.empty?
      raise FormatDecodeError.new("Unbalanced tag in XML.")
    end

    @handlers.each do |uri, handler|
      handler.decode_epilogue
    end

    @lastnode
  end

  def start_element(name, attrs)
    lastframe = @parsestack.last
    ns = parent = parent_encodingstyle = nil
    if lastframe
      ns = lastframe.ns.clone_ns
      parent = lastframe.node
      parent_encodingstyle = lastframe.encodingstyle
    else
      ns = XSD::NS.new
      parent = ParseFrame::NodeContainer.new(nil)
      parent_encodingstyle = nil
    end

    attrs = XSD::XMLParser.filter_ns(ns, attrs)
    encodingstyle = find_encodingstyle(ns, attrs)

    # Children's encodingstyle is derived from its parent.
    if encodingstyle.nil?
      if parent.node.is_a?(SOAPHeader)
        encodingstyle = LiteralNamespace
      else
        encodingstyle = parent_encodingstyle || @default_encodingstyle
      end
    end

    node = decode_tag(ns, name, attrs, parent, encodingstyle)

    @parsestack << ParseFrame.new(ns, name, node, encodingstyle)
  end

  def characters(text)
    lastframe = @parsestack.last
    if lastframe
      # Need not to be cloned because character does not have attr.
      ns = lastframe.ns
      parent = lastframe.node
      encodingstyle = lastframe.encodingstyle
      decode_text(ns, text, encodingstyle)
    else
      # Ignore Text outside of SOAP Envelope.
      p text if $DEBUG
    end
  end

  def end_element(name)
    lastframe = @parsestack.pop
    unless name == lastframe.name
      raise UnexpectedElementError.new("Closing element name '#{ name }' does not match with opening element '#{ lastframe.name }'.")
    end
    decode_tag_end(lastframe.ns, lastframe.node, lastframe.encodingstyle)
    @lastnode = lastframe.node.node
  end

private

  def find_encodingstyle(ns, attrs)
    attrs.each do |key, value|
      if (ns.compare(EnvelopeNamespace, AttrEncodingStyle, key))
	return value
      end
    end
    nil
  end

  def decode_tag(ns, name, attrs, parent, encodingstyle)
    ele = ns.parse(name)

    # Envelope based parsing.
    if ((ele.namespace == EnvelopeNamespace) ||
	(@allow_unqualified_element && ele.namespace.nil?))
      o = decode_soap_envelope(ns, ele, attrs, parent)
      return o if o
    end

    # Encoding based parsing.
    handler = find_handler(encodingstyle)
    if handler
      return handler.decode_tag(ns, ele, attrs, parent)
    else
      raise FormatDecodeError.new("Unknown encodingStyle: #{ encodingstyle }.")
    end
  end

  def decode_tag_end(ns, node, encodingstyle)
    return unless encodingstyle

    handler = find_handler(encodingstyle)
    if handler
      return handler.decode_tag_end(ns, node)
    else
      raise FormatDecodeError.new("Unknown encodingStyle: #{ encodingstyle }.")
    end
  end

  def decode_text(ns, text, encodingstyle)
    handler = find_handler(encodingstyle)

    if handler
      handler.decode_text(ns, text)
    else
      # How should I do?
    end
  end

  def decode_soap_envelope(ns, ele, attrs, parent)
    o = nil
    if ele.name == EleEnvelope
      o = SOAPEnvelope.new
      if ext = @opt[:external_content]
	ext.each do |k, v|
	  o.external_content[k] = v
	end
      end
    elsif ele.name == EleHeader
      unless parent.node.is_a?(SOAPEnvelope)
	raise FormatDecodeError.new("Header should be a child of Envelope.")
      end
      o = SOAPHeader.new
      parent.node.header = o
    elsif ele.name == EleBody
      unless parent.node.is_a?(SOAPEnvelope)
	raise FormatDecodeError.new("Body should be a child of Envelope.")
      end
      o = SOAPBody.new
      parent.node.body = o
    elsif ele.name == EleFault
      unless parent.node.is_a?(SOAPBody)
	raise FormatDecodeError.new("Fault should be a child of Body.")
      end
      o = SOAPFault.new
      parent.node.fault = o
    end
    o
  end

  def find_handler(encodingstyle)
    unless @handlers.key?(encodingstyle)
      handler_factory = SOAP::EncodingStyle::Handler.handler(encodingstyle) ||
	SOAP::EncodingStyle::Handler.handler(EncodingNamespace)
      handler = handler_factory.new(@parser.charset)
      handler.decode_typemap = @decode_typemap
      handler.decode_prologue
      @handlers[encodingstyle] = handler
    end
    @handlers[encodingstyle]
  end
end


end
