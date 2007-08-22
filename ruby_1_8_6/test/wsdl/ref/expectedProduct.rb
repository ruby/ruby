require 'xsd/qname'

# {urn:product}Rating
module Rating
  C_0 = "0"
  C_1 = "+1"
  C_1_2 = "-1"
end

# {urn:product}Product-Bag
class ProductBag
  @@schema_type = "Product-Bag"
  @@schema_ns = "urn:product"
  @@schema_attribute = {XSD::QName.new("urn:product", "version") => "SOAP::SOAPString", XSD::QName.new("urn:product", "yesno") => "SOAP::SOAPString"}
  @@schema_element = [["bag", ["Product[]", XSD::QName.new(nil, "bag")]], ["rating", ["SOAP::SOAPString[]", XSD::QName.new("urn:product", "Rating")]], ["product_Bag", [nil, XSD::QName.new("urn:product", "Product-Bag")]], ["comment_1", [nil, XSD::QName.new(nil, "comment_1")]], ["comment_2", ["Comment[]", XSD::QName.new(nil, "comment-2")]]]

  attr_accessor :bag
  attr_accessor :product_Bag
  attr_accessor :comment_1
  attr_accessor :comment_2

  def Rating
    @rating
  end

  def Rating=(value)
    @rating = value
  end

  def xmlattr_version
    (@__xmlattr ||= {})[XSD::QName.new("urn:product", "version")]
  end

  def xmlattr_version=(value)
    (@__xmlattr ||= {})[XSD::QName.new("urn:product", "version")] = value
  end

  def xmlattr_yesno
    (@__xmlattr ||= {})[XSD::QName.new("urn:product", "yesno")]
  end

  def xmlattr_yesno=(value)
    (@__xmlattr ||= {})[XSD::QName.new("urn:product", "yesno")] = value
  end

  def initialize(bag = [], rating = [], product_Bag = nil, comment_1 = [], comment_2 = [])
    @bag = bag
    @rating = rating
    @product_Bag = product_Bag
    @comment_1 = comment_1
    @comment_2 = comment_2
    @__xmlattr = {}
  end
end

# {urn:product}Creator
class Creator
  @@schema_type = "Creator"
  @@schema_ns = "urn:product"
  @@schema_element = []

  def initialize
  end
end

# {urn:product}Product
class Product
  @@schema_type = "Product"
  @@schema_ns = "urn:product"
  @@schema_element = [["name", ["SOAP::SOAPString", XSD::QName.new(nil, "name")]], ["rating", ["SOAP::SOAPString", XSD::QName.new("urn:product", "Rating")]]]

  attr_accessor :name

  def Rating
    @rating
  end

  def Rating=(value)
    @rating = value
  end

  def initialize(name = nil, rating = nil)
    @name = name
    @rating = rating
  end
end

# {urn:product}Comment
class Comment < String
end
