=begin
SOAP4R - SOAP EncodingStyle handler library
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


require 'soap/encodingstyle/handler'


module SOAP
module EncodingStyle


class SOAPHandler < Handler
  Namespace = SOAP::EncodingNamespace
  add_handler

  def initialize(charset = nil)
    super(charset)
    @refpool = []
    @idpool = []
    @textbuf = ''
    @is_first_top_ele = true
  end


  ###
  ## encode interface.
  #
  def encode_data(generator, ns, qualified, data, parent)
    attrs = encode_attrs(generator, ns, data, parent)

    if parent && parent.is_a?(SOAPArray) && parent.position
      attrs[ns.name(AttrPositionName)] = '[' << parent.position.join(',') << ']'
    end

    name = nil
    if qualified and data.elename.namespace
      SOAPGenerator.assign_ns(attrs, ns, data.elename.namespace)
      name = ns.name(data.elename)
    else
      name = data.elename.name
    end

    case data
    when SOAPReference
      attrs['href'] = '#' << data.refid
      generator.encode_tag(name, attrs)
    when SOAPRawString
      generator.encode_tag(name, attrs)
      generator.encode_rawstring(data.to_s)
    when XSD::XSDString
      generator.encode_tag(name, attrs)
      generator.encode_string(@charset ? XSD::Charset.encoding_to_xml(data.to_s, @charset) : data.to_s)
    when XSD::XSDAnySimpleType
      generator.encode_tag(name, attrs)
      generator.encode_string(data.to_s)
    when SOAPStruct
      generator.encode_tag(name, attrs)
      data.each do |key, value|
	yield(value, false)
      end
    when SOAPArray
      generator.encode_tag(name, attrs)
      data.traverse do |child, *rank|
	data.position = data.sparse ? rank : nil
	yield(child, false)
      end
    else
      raise EncodingStyleError.new(
	"Unknown object:#{ data } in this encodingStyle.")
    end
  end

  def encode_data_end(generator, ns, qualified, data, parent)
    name = if qualified and data.elename.namespace
        ns.name(data.elename)
      else
        data.elename.name
      end
    cr = data.is_a?(SOAPCompoundtype)
    generator.encode_tag_end(name, cr)
  end


  ###
  ## decode interface.
  #
  class SOAPTemporalObject
    attr_accessor :parent
    attr_accessor :position
    attr_accessor :id
    attr_accessor :root

    def initialize
      @parent = nil
      @position = nil
      @id = nil
      @root = nil
    end
  end

  class SOAPUnknown < SOAPTemporalObject
    attr_reader :type
    attr_accessor :definedtype
    attr_reader :extraattr

    def initialize(handler, elename, type, extraattr)
      super()
      @handler = handler
      @elename = elename
      @type = type
      @extraattr = extraattr
      @definedtype = nil
    end

    def as_struct
      o = SOAPStruct.decode(@elename, @type)
      o.id = @id
      o.root = @root
      o.parent = @parent
      o.position = @position
      o.extraattr.update(@extraattr)
      @handler.decode_parent(@parent, o)
      o
    end

    def as_string
      o = SOAPString.decode(@elename)
      o.id = @id
      o.root = @root
      o.parent = @parent
      o.position = @position
      o.extraattr.update(@extraattr)
      @handler.decode_parent(@parent, o)
      o
    end

    def as_nil
      o = SOAPNil.decode(@elename)
      o.id = @id
      o.root = @root
      o.parent = @parent
      o.position = @position
      o.extraattr.update(@extraattr)
      @handler.decode_parent(@parent, o)
      o
    end
  end

  def decode_tag(ns, elename, attrs, parent)
    # ToDo: check if @textbuf is empty...
    @textbuf = ''
    is_nil, type, arytype, root, offset, position, href, id, extraattr =
      decode_attrs(ns, attrs)
    o = nil
    if is_nil
      o = SOAPNil.decode(elename)
    elsif href
      o = SOAPReference.decode(elename, href)
      @refpool << o
    elsif @decode_typemap &&
	(parent.node.class != SOAPBody || @is_first_top_ele)
      # multi-ref element should be parsed by decode_tag_by_type.
      @is_first_top_ele = false
      o = decode_tag_by_wsdl(ns, elename, type, parent.node, arytype, extraattr)
    else
      o = decode_tag_by_type(ns, elename, type, parent.node, arytype, extraattr)
    end

    if o.is_a?(SOAPArray)
      if offset
	o.offset = decode_arypos(offset)
	o.sparse = true
      else
	o.sparse = false
      end
    end

    o.parent = parent
    o.id = id
    o.root = root
    o.position = position

    unless o.is_a?(SOAPTemporalObject)
      @idpool << o if o.id
      decode_parent(parent, o)
    end
    o
  end

  def decode_tag_end(ns, node)
    o = node.node
    if o.is_a?(SOAPUnknown)
      newnode = if /\A\s*\z/ =~ @textbuf
	o.as_struct
      else
	o.as_string
      end
      if newnode.id
	@idpool << newnode
      end
      node.replace_node(newnode)
      o = node.node
    end
    if o.is_a?(SOAPCompoundtype)
      o.definedtype = nil
    end

    decode_textbuf(o)
    @textbuf = ''
  end

  def decode_text(ns, text)
    # @textbuf is set at decode_tag_end.
    @textbuf << text
  end

  def decode_prologue
    @refpool.clear
    @idpool.clear
    @is_first_top_ele = true
  end

  def decode_epilogue
    decode_resolve_id
  end

  def decode_parent(parent, node)
    case parent.node
    when SOAPUnknown
      newparent = parent.node.as_struct
      node.parent = newparent
      if newparent.id
	@idpool << newparent
      end
      parent.replace_node(newparent)
      decode_parent(parent, node)

    when SOAPStruct
      parent.node.add(node.elename.name, node)
      node.parent = parent.node

    when SOAPArray
      if node.position
	parent.node[*(decode_arypos(node.position))] = node
	parent.node.sparse = true
      else
	parent.node.add(node)
      end
      node.parent = parent.node

    when SOAPBasetype
      raise EncodingStyleError.new("SOAP base type must not have a child.")

    else
      raise EncodingStyleError.new("Illegal parent: #{ parent.node }.")
    end
  end

private

  def content_ranksize(typename)
    typename.scan(/\[[\d,]*\]$/)[0]
  end

  def content_typename(typename)
    typename.sub(/\[,*\]$/, '')
  end

  def create_arytype(ns, data)
    XSD::QName.new(data.arytype.namespace,
      content_typename(data.arytype.name) << '[' << data.size.join(',') << ']')
  end

  def encode_attrs(generator, ns, data, parent)
    return {} if data.is_a?(SOAPReference)
    attrs = {}

    if !parent || parent.encodingstyle != EncodingNamespace
      if @generate_explicit_type
        SOAPGenerator.assign_ns(attrs, ns, EnvelopeNamespace)
        SOAPGenerator.assign_ns(attrs, ns, EncodingNamespace)
        attrs[ns.name(AttrEncodingStyleName)] = EncodingNamespace
      end
      data.encodingstyle = EncodingNamespace
    end

    if data.is_a?(SOAPNil)
      attrs[ns.name(XSD::AttrNilName)] = XSD::NilValue
    elsif @generate_explicit_type
      if data.type.namespace
        SOAPGenerator.assign_ns(attrs, ns, data.type.namespace)
      end
      if data.is_a?(SOAPArray)
	if data.arytype.namespace
          SOAPGenerator.assign_ns(attrs, ns, data.arytype.namespace)
   	end
	attrs[ns.name(AttrArrayTypeName)] = ns.name(create_arytype(ns, data))
	if data.type.name
	  attrs[ns.name(XSD::AttrTypeName)] = ns.name(data.type)
	end
      elsif parent && parent.is_a?(SOAPArray) && (parent.arytype == data.type)
	# No need to add.
      elsif !data.type.namespace
	# No need to add.
      else
	attrs[ns.name(XSD::AttrTypeName)] = ns.name(data.type)
      end
    end

    data.extraattr.each do |key, value|
      SOAPGenerator.assign_ns(attrs, ns, key.namespace)
      attrs[ns.name(key)] = encode_attr_value(generator, ns, key, value)
    end
    if data.id
      attrs['id'] = data.id
    end
    attrs
  end

  def encode_attr_value(generator, ns, qname, value)
    if value.is_a?(SOAPType)
      refid = SOAPReference.create_refid(value)
      value.id = refid
      generator.add_reftarget(qname.name, value)
      '#' + refid
    else
      value.to_s
    end
  end

  def decode_tag_by_wsdl(ns, elename, typestr, parent, arytypestr, extraattr)
    if parent.class == SOAPBody
      # Unqualified name is allowed here.
      type = @decode_typemap[elename] || @decode_typemap.find_name(elename.name)
      unless type
	raise EncodingStyleError.new("Unknown operation '#{ elename }'.")
      end
      o = SOAPStruct.new(elename)
      o.definedtype = type
      return o
    end

    if parent.type == XSD::AnyTypeName
      return decode_tag_by_type(ns, elename, typestr, parent, arytypestr,
	extraattr)
    end

    # parent.definedtype is nil means the parent is SOAPUnknown.  SOAPUnknown is
    # generated by decode_tag_by_type when its type is anyType.
    parenttype = parent.definedtype || @decode_typemap[parent.type]
    unless parenttype
      raise EncodingStyleError.new("Unknown type '#{ parent.type }'.")
    end
    typename = parenttype.child_type(elename)
    if typename
      if (klass = TypeMap[typename])
	return klass.decode(elename)
      elsif typename == XSD::AnyTypeName
	return decode_tag_by_type(ns, elename, typestr, parent, arytypestr,
	  extraattr)
      end
    end

    type = if typename
	@decode_typemap[typename]
      else
	parenttype.child_defined_complextype(elename)
      end
    unless type
      raise EncodingStyleError.new("Unknown type '#{ typename }'.")
    end

    case type.compoundtype
    when :TYPE_STRUCT
      o = SOAPStruct.decode(elename, typename)
      o.definedtype = type
      return o
    when :TYPE_ARRAY
      expected_arytype = type.find_arytype
      actual_arytype = if arytypestr
	  XSD::QName.new(expected_arytype.namespace,
	    content_typename(expected_arytype.name) <<
	    content_ranksize(arytypestr))
	else
       	  expected_arytype
	end
      o = SOAPArray.decode(elename, typename, actual_arytype)
      o.definedtype = type
      return o
    end
    return nil
  end

  def decode_tag_by_type(ns, elename, typestr, parent, arytypestr, extraattr)
    if arytypestr
      type = typestr ? ns.parse(typestr) : ValueArrayName
      node = SOAPArray.decode(elename, type, ns.parse(arytypestr))
      node.extraattr.update(extraattr)
      return node
    end

    type = nil
    if typestr
      type = ns.parse(typestr)
    elsif parent.is_a?(SOAPArray)
      type = parent.arytype
    else
      # Since it's in dynamic(without any type) encoding process,
      # assumes entity as its type itself.
      #   <SOAP-ENC:Array ...> => type Array in SOAP-ENC.
      #   <Country xmlns="foo"> => type Country in foo.
      type = elename
    end

    if (klass = TypeMap[type])
      node = klass.decode(elename)
      node.extraattr.update(extraattr)
      return node
    end

    # Unknown type... Struct or String
    SOAPUnknown.new(self, elename, type, extraattr)
  end

  def decode_textbuf(node)
    case node
    when XSD::XSDHexBinary, XSD::XSDBase64Binary
      node.set_encoded(@textbuf)
    when XSD::XSDString
      if @charset
	node.set(XSD::Charset.encoding_from_xml(@textbuf, @charset))
      else
	node.set(@textbuf)
      end
    when SOAPNil
      # Nothing to do.
    when SOAPBasetype
      node.set(@textbuf)
    else
      # Nothing to do...
    end
  end

  NilLiteralMap = {
    'true' => true,
    '1' => true,
    'false' => false,
    '0' => false
  }
  RootLiteralMap = {
    '1' => 1,
    '0' => 0
  }
  def decode_attrs(ns, attrs)
    is_nil = false
    type = nil
    arytype = nil
    root = nil
    offset = nil
    position = nil
    href = nil
    id = nil
    extraattr = {}

    attrs.each do |key, value|
      qname = ns.parse(key)
      case qname.namespace
      when XSD::InstanceNamespace
        case qname.name
        when XSD::NilLiteral
          is_nil = NilLiteralMap[value] or
            raise EncodingStyleError.new("Cannot accept attribute value: #{ value } as the value of xsi:#{ XSD::NilLiteral } (expected 'true', 'false', '1', or '0').")
          next
        when XSD::AttrType
          type = value
          next
        end
      when EncodingNamespace
        case qname.name
        when AttrArrayType
          arytype = value
          next
        when AttrRoot
          root = RootLiteralMap[value] or
            raise EncodingStyleError.new(
	      "Illegal root attribute value: #{ value }.")
          next
        when AttrOffset
          offset = value
          next
        when AttrPosition
          position = value
          next
        end
      end
      if key == 'href'
        href = value
        next
      elsif key == 'id'
        id = value
        next
      end
      extraattr[qname] = decode_attr_value(ns, qname, value)
    end

    return is_nil, type, arytype, root, offset, position, href, id, extraattr
  end

  def decode_attr_value(ns, qname, value)
    if /\A#/ =~ value
      o = SOAPReference.new(value)
      @refpool << o
      o
    else
      value
    end
  end

  def decode_arypos(position)
    /^\[(.+)\]$/ =~ position
    $1.split(',').collect { |s| s.to_i }
  end

  def decode_resolve_id
    count = @refpool.length	# To avoid infinite loop
    while !@refpool.empty? && count > 0
      @refpool = @refpool.find_all { |ref|
	o = @idpool.find { |item|
	  '#' + item.id == ref.refid
	}
	unless o
	  raise EncodingStyleError.new("Unresolved reference: #{ ref.refid }.")
	end
	if o.is_a?(SOAPReference)
	  true
	else
	  ref.__setobj__(o)
	  false
	end
      }
      count -= 1
    end
  end
end

SOAPHandler.new


end
end
