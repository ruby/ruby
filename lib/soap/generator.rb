=begin
SOAP4R - SOAP XML Instance Generator library.
Copyright (C) 2001, 2003  NAKAMURA, Hiroshi.

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


require 'xsd/ns'
require 'soap/soap'
require 'soap/baseData'
require 'soap/encodingstyle/handler'


module SOAP


###
## CAUTION: MT-unsafe
#
class SOAPGenerator
  include SOAP

  class FormatEncodeError < Error; end

public

  attr_accessor :charset
  attr_accessor :default_encodingstyle
  attr_accessor :generate_explicit_type
  attr_accessor :pretty

  def initialize(opt = {})
    @reftarget = nil
    @handlers = {}
    @charset = opt[:charset] || XSD::Charset.encoding_label
    @default_encodingstyle = opt[:default_encodingstyle] || EncodingNamespace
    @generate_explicit_type =
      opt.key?(:generate_explicit_type) ? opt[:generate_explicit_type] : true
    @pretty = true # opt[:pretty]
  end

  def generate(obj, io = nil)
    prologue
    @handlers.each do |uri, handler|
      handler.encode_prologue
    end

    io = '' if io.nil?

    ns = XSD::NS.new
    io << xmldecl
    encode_data(io, ns, true, obj, nil, 0)

    @handlers.each do |uri, handler|
      handler.encode_epilogue
    end
    epilogue

    io
  end

  def encode_data(buf, ns, qualified, obj, parent, indent)
    if obj.is_a?(SOAPEnvelopeElement)
      encode_element(buf, ns, qualified, obj, parent, indent)
      return
    end

    if @reftarget && !obj.precedents.empty?
      @reftarget.add(obj.elename.name, obj)
      ref = SOAPReference.new
      ref.elename.name = obj.elename.name
      ref.__setobj__(obj)
      obj.precedents.clear	# Avoid cyclic delay.
      obj.encodingstyle = parent.encodingstyle
      # SOAPReference is encoded here.
      obj = ref
    end

    encodingstyle = obj.encodingstyle
    # Children's encodingstyle is derived from its parent.
    encodingstyle ||= parent.encodingstyle if parent
    obj.encodingstyle = encodingstyle

    handler = find_handler(encodingstyle || @default_encodingstyle)
    unless handler
      raise FormatEncodeError.new("Unknown encodingStyle: #{ encodingstyle }.")
    end

    if !obj.elename.name
      raise FormatEncodeError.new("Element name not defined: #{ obj }.")
    end

    indent_str = ' ' * indent
    child_indent = @pretty ? indent + 2 : indent
    handler.encode_data(buf, ns, qualified, obj, parent, indent_str) do |child, child_q|
      encode_data(buf, ns.clone_ns, child_q, child, obj, child_indent)
    end
    handler.encode_data_end(buf, ns, qualified, obj, parent, indent_str)
  end

  def encode_element(buf, ns, qualified, obj, parent, indent)
    indent_str = ' ' * indent
    child_indent = @pretty ? indent + 2 : indent
    attrs = {}
    if obj.is_a?(SOAPBody)
      @reftarget = obj
      obj.encode(buf, ns, attrs, indent_str) do |child, child_q|
        encode_data(buf, ns.clone_ns, child_q, child, obj, child_indent)
      end
      @reftarget = nil
    else
      if obj.is_a?(SOAPEnvelope)
        # xsi:nil="true" can appear even if dumping without explicit type.
        SOAPGenerator.assign_ns(attrs, ns,
	  XSD::InstanceNamespace, XSINamespaceTag)
        if @generate_explicit_type
          SOAPGenerator.assign_ns(attrs, ns, XSD::Namespace, XSDNamespaceTag)
        end
      end
      obj.encode(buf, ns, attrs, indent_str) do |child, child_q|
        encode_data(buf, ns.clone_ns, child_q, child, obj, child_indent)
      end
    end
  end

  def self.assign_ns(attrs, ns, namespace, tag = nil)
    unless ns.assigned?(namespace)
      tag = ns.assign(namespace, tag)
      attrs['xmlns:' << tag] = namespace
    end
  end

  def self.encode_tag(buf, elename, attrs = nil, indent = '')
    if attrs
      buf << "\n#{ indent }<#{ elename }" <<
        attrs.collect { |key, value|
          %Q[ #{ key }="#{ value }"]
        }.join <<
        '>'
    else
      buf << "\n#{ indent }<#{ elename }>"
    end
  end

  def self.encode_tag_end(buf, elename, indent = '', cr = nil)
    if cr
      buf << "\n#{ indent }</#{ elename }>"
    else
      buf << "</#{ elename }>"
    end
  end

  EncodeMap = {
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
    '\'' => '&apos;',
    "\r" => '&#xd;'
  }
  EncodeCharRegexp = Regexp.new("[#{EncodeMap.keys.join}]")
  def self.encode_str(str)
    str.gsub(EncodeCharRegexp) { |c| EncodeMap[c] }
  end

private

  def prologue
  end

  def epilogue
  end

  def find_handler(encodingstyle)
    unless @handlers.key?(encodingstyle)
      handler = SOAP::EncodingStyle::Handler.handler(encodingstyle).new(@charset)
      handler.generate_explicit_type = @generate_explicit_type
      handler.encode_prologue
      @handlers[encodingstyle] = handler
    end
    @handlers[encodingstyle]
  end

  def xmldecl
    if @charset
      %Q[<?xml version="1.0" encoding="#{ @charset }" ?>]
    else
      %Q[<?xml version="1.0" ?>]
    end
  end
end


end
