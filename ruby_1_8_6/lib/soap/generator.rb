# SOAP4R - SOAP XML Instance Generator library.
# Copyright (C) 2001, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
  attr_accessor :use_numeric_character_reference

  def initialize(opt = {})
    @reftarget = nil
    @handlers = {}
    @charset = opt[:charset] || XSD::Charset.xml_encoding_label
    @default_encodingstyle = opt[:default_encodingstyle] || EncodingNamespace
    @generate_explicit_type =
      opt.key?(:generate_explicit_type) ? opt[:generate_explicit_type] : true
    @elementformdefault = opt[:elementformdefault]
    @attributeformdefault = opt[:attributeformdefault]
    @use_numeric_character_reference = opt[:use_numeric_character_reference]
    @indentstr = opt[:no_indent] ? '' : '  '
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
    encode_data(ns, obj, nil)

    @handlers.each do |uri, handler|
      handler.encode_epilogue
    end
    epilogue

    @buf
  end

  def encode_data(ns, obj, parent)
    if obj.is_a?(SOAPEnvelopeElement)
      encode_element(ns, obj, parent)
      return
    end
    if @reftarget && !obj.precedents.empty?
      add_reftarget(obj.elename.name, obj)
      ref = SOAPReference.new(obj)
      ref.elename = ref.elename.dup_name(obj.elename.name)
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
    handler.encode_data(self, ns, obj, parent)
    handler.encode_data_end(self, ns, obj, parent)
  end

  def add_reftarget(name, node)
    unless @reftarget
      raise FormatEncodeError.new("Reftarget is not defined.")
    end
    @reftarget.add(name, node)
  end

  def encode_child(ns, child, parent)
    indent_backup, @indent = @indent, @indent + @indentstr
    encode_data(ns.clone_ns, child, parent)
    @indent = indent_backup
  end

  def encode_element(ns, obj, parent)
    attrs = {}
    if obj.is_a?(SOAPBody)
      @reftarget = obj
      obj.encode(self, ns, attrs) do |child|
	indent_backup, @indent = @indent, @indent + @indentstr
        encode_data(ns.clone_ns, child, obj)
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
      obj.encode(self, ns, attrs) do |child|
	indent_backup, @indent = @indent, @indent + @indentstr
        encode_data(ns.clone_ns, child, obj)
	@indent = indent_backup
      end
    end
  end

  def encode_name(ns, data, attrs)
    if element_local?(data)
      data.elename.name
    else
      if element_qualified?(data)
        SOAPGenerator.assign_ns(attrs, ns, data.elename.namespace, '')
      else
        SOAPGenerator.assign_ns(attrs, ns, data.elename.namespace)
      end
      ns.name(data.elename)
    end
  end

  def encode_name_end(ns, data)
    if element_local?(data)
      data.elename.name
    else
      ns.name(data.elename)
    end
  end

  def encode_tag(elename, attrs = nil)
    if !attrs or attrs.empty?
      @buf << "\n#{ @indent }<#{ elename }>"
    elsif attrs.size == 1
      key, value = attrs.shift
      @buf << %Q[\n#{ @indent }<#{ elename } #{ key }="#{ value }">]
    else
      @buf << "\n#{ @indent }<#{ elename } " <<
        attrs.collect { |key, value|
          %Q[#{ key }="#{ value }"]
        }.join("\n#{ @indent }#{ @indentstr * 2 }") <<
	'>'
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
    if @use_numeric_character_reference and !XSD::Charset.is_us_ascii(str)
      str.gsub!(EncodeCharRegexp) { |c| EncodeMap[c] }
      @buf << str.unpack("U*").collect { |c|
        if c == 0x9 or c == 0xa or c == 0xd or (c >= 0x20 and c <= 0x7f)
          c.chr
        else
          sprintf("&#x%x;", c)
        end
      }.join
    else
      @buf << str.gsub(EncodeCharRegexp) { |c| EncodeMap[c] }
    end
  end

  def element_local?(element)
    element.elename.namespace.nil?
  end

  def element_qualified?(element)
    if element.respond_to?(:qualified)
      if element.qualified.nil?
        @elementformdefault
      else
        element.qualified
      end
    else
      @elementformdefault
    end
  end

  def self.assign_ns(attrs, ns, namespace, tag = nil)
    if namespace.nil?
      raise FormatEncodeError.new("empty namespace")
    end
    unless ns.assigned?(namespace)
      tag = ns.assign(namespace, tag)
      if tag == ''
        attr = 'xmlns'
      else
        attr = "xmlns:#{tag}"
      end
      attrs[attr] = namespace
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
