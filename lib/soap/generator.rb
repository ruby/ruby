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

  def initialize(opt = {})
    @reftarget = nil
    @handlers = {}
    @charset = opt[:charset] || XSD::Charset.encoding_label
    @default_encodingstyle = opt[:default_encodingstyle] || EncodingNamespace
    @generate_explicit_type =
      opt.key?(:generate_explicit_type) ? opt[:generate_explicit_type] : true
    @buf = @indent = @curr = nil
  end

  def generate(obj, io = nil)
    @buf = io || ''
    @indent = ''

    prologue
    @handlers.each do |uri, handler|
      handler.encode_prologue
    end

    ns = XSD::NS.new
    @buf << xmldecl
    encode_data(ns, true, obj, nil)

    @handlers.each do |uri, handler|
      handler.encode_epilogue
    end
    epilogue

    @buf
  end

  def encode_data(ns, qualified, obj, parent)
    if obj.is_a?(SOAPEnvelopeElement)
      encode_element(ns, qualified, obj, parent)
      return
    end

    if @reftarget && !obj.precedents.empty?
      add_reftarget(obj.elename.name, obj)
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

    handler.encode_data(self, ns, qualified, obj, parent) do |child, child_q|
      indent_backup, @indent = @indent, @indent + '  '
      encode_data(ns.clone_ns, child_q, child, obj)
      @indent = indent_backup
    end
    handler.encode_data_end(self, ns, qualified, obj, parent)
  end

  def add_reftarget(name, node)
    unless @reftarget
      raise FormatEncodeError.new("Reftarget is not defined.")
    end
    @reftarget.add(name, node)
  end

  def encode_element(ns, qualified, obj, parent)
    attrs = {}
    if obj.is_a?(SOAPBody)
      @reftarget = obj
      obj.encode(self, ns, attrs) do |child, child_q|
	indent_backup, @indent = @indent, @indent + '  '
        encode_data(ns.clone_ns, child_q, child, obj)
	@indent = indent_backup
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
      obj.encode(self, ns, attrs) do |child, child_q|
	indent_backup, @indent = @indent, @indent + '  '
        encode_data(ns.clone_ns, child_q, child, obj)
	@indent = indent_backup
      end
    end
  end

  def encode_tag(elename, attrs = nil)
    if attrs
      @buf << "\n#{ @indent }<#{ elename }" <<
        attrs.collect { |key, value|
          %Q[ #{ key }="#{ value }"]
        }.join <<
        '>'
    else
      @buf << "\n#{ @indent }<#{ elename }>"
    end
  end

  def encode_tag_end(elename, cr = nil)
    if cr
      @buf << "\n#{ @indent }</#{ elename }>"
    else
      @buf << "</#{ elename }>"
    end
  end

  def encode_rawstring(str)
    @buf << str
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
  def encode_string(str)
    @buf << str.gsub(EncodeCharRegexp) { |c| EncodeMap[c] }
  end

  def self.assign_ns(attrs, ns, namespace, tag = nil)
    if namespace and !ns.assigned?(namespace)
      tag = ns.assign(namespace, tag)
      attrs['xmlns:' << tag] = namespace
    end
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
