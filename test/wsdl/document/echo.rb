require 'xsd/qname'

# {urn:docrpc}echoele
class Echoele
  @@schema_type = "echoele"
  @@schema_ns = "urn:docrpc"
  @@schema_attribute = {XSD::QName.new(nil, "attr_string") => "SOAP::SOAPString", XSD::QName.new(nil, "attr-int") => "SOAP::SOAPInt"}
  @@schema_element = [["struct1", ["Echo_struct", XSD::QName.new(nil, "struct1")]], ["struct_2", ["Echo_struct", XSD::QName.new(nil, "struct-2")]]]

  attr_accessor :struct1
  attr_accessor :struct_2

  def xmlattr_attr_string
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr_string")]
  end

  def xmlattr_attr_string=(value)
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr_string")] = value
  end

  def xmlattr_attr_int
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr-int")]
  end

  def xmlattr_attr_int=(value)
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr-int")] = value
  end

  def initialize(struct1 = nil, struct_2 = nil)
    @struct1 = struct1
    @struct_2 = struct_2
    @__xmlattr = {}
  end
end

# {urn:docrpc}echo_response
class Echo_response
  @@schema_type = "echo_response"
  @@schema_ns = "urn:docrpc"
  @@schema_attribute = {XSD::QName.new(nil, "attr_string") => "SOAP::SOAPString", XSD::QName.new(nil, "attr-int") => "SOAP::SOAPInt"}
  @@schema_element = [["struct1", ["Echo_struct", XSD::QName.new(nil, "struct1")]], ["struct_2", ["Echo_struct", XSD::QName.new(nil, "struct-2")]]]

  attr_accessor :struct1
  attr_accessor :struct_2

  def xmlattr_attr_string
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr_string")]
  end

  def xmlattr_attr_string=(value)
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr_string")] = value
  end

  def xmlattr_attr_int
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr-int")]
  end

  def xmlattr_attr_int=(value)
    (@__xmlattr ||= {})[XSD::QName.new(nil, "attr-int")] = value
  end

  def initialize(struct1 = nil, struct_2 = nil)
    @struct1 = struct1
    @struct_2 = struct_2
    @__xmlattr = {}
  end
end

# {urn:docrpc}echo_struct
class Echo_struct
  @@schema_type = "echo_struct"
  @@schema_ns = "urn:docrpc"
  @@schema_attribute = {XSD::QName.new(nil, "m_attr") => "SOAP::SOAPString"}
  @@schema_element = [["m_string", ["SOAP::SOAPString", XSD::QName.new(nil, "m_string")]], ["m_datetime", ["SOAP::SOAPDateTime", XSD::QName.new(nil, "m_datetime")]]]

  attr_accessor :m_string
  attr_accessor :m_datetime

  def xmlattr_m_attr
    (@__xmlattr ||= {})[XSD::QName.new(nil, "m_attr")]
  end

  def xmlattr_m_attr=(value)
    (@__xmlattr ||= {})[XSD::QName.new(nil, "m_attr")] = value
  end

  def initialize(m_string = nil, m_datetime = nil)
    @m_string = m_string
    @m_datetime = m_datetime
    @__xmlattr = {}
  end
end
