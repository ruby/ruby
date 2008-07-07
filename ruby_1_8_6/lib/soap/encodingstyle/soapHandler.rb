# SOAP4R - SOAP EncodingStyle handler library
# Copyright (C) 2001, 2003, 2005  NAKAMURA, Hiroshi <nahi@ruby-lang.org>.

# This program is copyrighted free software by NAKAMURA, Hiroshi.  You can
# redistribute it and/or modify it under the same terms of Ruby's license;
# either the dual license version in 2003, or any later version.


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
  def encode_data(generator, ns, data, parent)
    attrs = encode_attrs(generator, ns, data, parent)
    if parent && parent.is_a?(SOAPArray) && parent.position
      attrs[ns.name(AttrPositionName)] = "[#{parent.position.join(',')}]"
    end
    name = generator.encode_name(ns, data, attrs)
    case data
    when SOAPReference
      attrs['href'] = data.refidstr
      generator.encode_tag(name, attrs)
    when SOAPExternalReference
      data.referred
      attrs['href'] = data.refidstr
      generator.encode_tag(name, attrs)
    when SOAPRawString
      generator.encode_tag(name, attrs)
      generator.encode_rawstring(data.to_s)
    when XSD::XSDString
      generator.encode_tag(name, attrs)
      generator.encode_string(@charset ?
	XSD::Charset.encoding_to_xml(data.to_s, @charset) : data.to_s)
    when XSD::XSDAnySimpleType
      generator.encode_tag(name, attrs)
      generator.encode_string(data.to_s)
    when SOAPStruct
      generator.encode_tag(name, attrs)
      data.each do |key, value|
        generator.encode_child(ns, value, data)
      end
    when SOAPArray
      generator.encode_tag(name, attrs)
      data.traverse do |child, *rank|
	data.position = data.sparse ? rank : nil
        generator.encode_child(ns, child, data)
      end
    else
      raise EncodingStyleError.new(
	"unknown object:#{data} in this encodingStyle")
    end
  end

  def encode_data_end(generator, ns, data, parent)
    name = generator.encode_name_end(ns, data)
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
    @textbuf = ''
    is_nil, type, arytype, root, offset, position, href, id, extraattr =
      decode_attrs(ns, attrs)
    o = nil
    if is_nil
      o = SOAPNil.decode(elename)
    elsif href
      o = SOAPReference.decode(elename, href)
      @refpool << o
    elsif @decode_typemap
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
    decode_textbuf(o)
    # unlink definedtype
    o.definedtype = nil
  end

  def decode_text(ns, text)
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
    return unless parent.node
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
    else
      raise EncodingStyleError.new("illegal parent: #{parent.node}")
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
      content_typename(data.arytype.name) + "[#{data.size.join(',')}]")
  end

  def encode_attrs(generator, ns, data, parent)
    attrs = {}
    return attrs if data.is_a?(SOAPReference)

    if !parent || parent.encodingstyle != EncodingNamespace
      if @generate_explicit_type
        SOAPGenerator.assign_ns(attrs, ns, EnvelopeNamespace)
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
	SOAPGenerator.assign_ns(attrs, ns, EncodingNamespace)
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
      ref = SOAPReference.new(value)
      generator.add_reftarget(qname.name, value)
      ref.refidstr
    else
      value.to_s
    end
  end

  def decode_tag_by_wsdl(ns, elename, typestr, parent, arytypestr, extraattr)
    o = nil
    if parent.class == SOAPBody
      # root element: should branch by root attribute?
      if @is_first_top_ele
	# Unqualified name is allowed here.
	@is_first_top_ele = false
	type = @decode_typemap[elename] ||
	  @decode_typemap.find_name(elename.name)
	if type
	  o = SOAPStruct.new(elename)
	  o.definedtype = type
	  return o
	end
      end
      # multi-ref element.
      if typestr
	typename = ns.parse(typestr)
	typedef = @decode_typemap[typename]
	if typedef
          return decode_definedtype(elename, typename, typedef, arytypestr)
	end
      end
      return decode_tag_by_type(ns, elename, typestr, parent, arytypestr,
	extraattr)
    end

    if parent.type == XSD::AnyTypeName
      return decode_tag_by_type(ns, elename, typestr, parent, arytypestr,
	extraattr)
    end

    # parent.definedtype == nil means the parent is SOAPUnknown.  SOAPUnknown
    # is generated by decode_tag_by_type when its type is anyType.
    parenttype = parent.definedtype || @decode_typemap[parent.type]
    unless parenttype
      return decode_tag_by_type(ns, elename, typestr, parent, arytypestr,
	extraattr)
    end

    definedtype_name = parenttype.child_type(elename)
    if definedtype_name and (klass = TypeMap[definedtype_name])
      return decode_basetype(klass, elename)
    elsif definedtype_name == XSD::AnyTypeName
      return decode_tag_by_type(ns, elename, typestr, parent, arytypestr,
	extraattr)
    end

    if definedtype_name
      typedef = @decode_typemap[definedtype_name]
    else
      typedef = parenttype.child_defined_complextype(elename)
    end
    decode_definedtype(elename, definedtype_name, typedef, arytypestr)
  end

  def decode_definedtype(elename, typename, typedef, arytypestr)
    unless typedef
      raise EncodingStyleError.new("unknown type '#{typename}'")
    end
    if typedef.is_a?(::WSDL::XMLSchema::SimpleType)
      decode_defined_simpletype(elename, typename, typedef, arytypestr)
    else
      decode_defined_complextype(elename, typename, typedef, arytypestr)
    end
  end

  def decode_basetype(klass, elename)
    klass.decode(elename)
  end

  def decode_defined_simpletype(elename, typename, typedef, arytypestr)
    o = decode_basetype(TypeMap[typedef.base], elename)
    o.definedtype = typedef
    o
  end

  def decode_defined_complextype(elename, typename, typedef, arytypestr)
    case typedef.compoundtype
    when :TYPE_STRUCT, :TYPE_MAP
      o = SOAPStruct.decode(elename, typename)
      o.definedtype = typedef
      return o
    when :TYPE_ARRAY
      expected_arytype = typedef.find_arytype
      if arytypestr
	actual_arytype = XSD::QName.new(expected_arytype.namespace,
	  content_typename(expected_arytype.name) <<
	  content_ranksize(arytypestr))
	o = SOAPArray.decode(elename, typename, actual_arytype)
      else
	o = SOAPArray.new(typename, 1, expected_arytype)
	o.elename = elename
      end
      o.definedtype = typedef
      return o
    when :TYPE_EMPTY
      o = SOAPNil.decode(elename)
      o.definedtype = typedef
      return o
    else
      raise RuntimeError.new(
        "Unknown kind of complexType: #{typedef.compoundtype}")
    end
    nil
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
      node = decode_basetype(klass, elename)
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
	@textbuf = XSD::Charset.encoding_from_xml(@textbuf, @charset)
      end
      if node.definedtype
        node.definedtype.check_lexical_format(@textbuf)
      end
      node.set(@textbuf)
    when SOAPNil
      # Nothing to do.
    when SOAPBasetype
      node.set(@textbuf)
    else
      # Nothing to do...
    end
    @textbuf = ''
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
            raise EncodingStyleError.new("cannot accept attribute value: #{value} as the value of xsi:#{XSD::NilLiteral} (expected 'true', 'false', '1', or '0')")
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
	      "illegal root attribute value: #{value}")
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
      qname = ns.parse_local(key)
      extraattr[qname] = decode_attr_value(ns, qname, value)
    end

    return is_nil, type, arytype, root, offset, position, href, id, extraattr
  end

  def decode_attr_value(ns, qname, value)
    if /\A#/ =~ value
      o = SOAPReference.decode(nil, value)
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
	  item.id == ref.refid
	}
	if o.is_a?(SOAPReference)
	  true	# link of link.
	elsif o
	  ref.__setobj__(o)
	  false
	elsif o = ref.rootnode.external_content[ref.refid]
	  ref.__setobj__(o)
      	  false
	else
	  raise EncodingStyleError.new("unresolved reference: #{ref.refid}")
	end
      }
      count -= 1
    end
  end
end

SOAPHandler.new


end
end
