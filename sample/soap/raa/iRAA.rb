require 'soap/mapping'


module RAA; extend SOAP


InterfaceNS = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"
MappingRegistry = SOAP::Mapping::Registry.new

Methods = [
  ['getAllListings', ['retval', 'return']],
  ['getProductTree', ['retval', 'return']],
  ['getInfoFromCategory', ['in', 'category'], [ 'retval', 'return']],
  ['getModifiedInfoSince', ['in', 'time'], [ 'retval', 'return']],
  ['getInfoFromName', ['in', 'name'], ['retval', 'return']],
]


class Category
  include SOAP::Marshallable

  @@schema_type = 'Category'
  @@schema_ns = InterfaceNS

  attr_reader :major, :minor

  def initialize(major, minor = nil)
    @major = major
    @minor = minor
  end

  def to_s
    "#{ @major }/#{ @minor }"
  end

  def ==(rhs)
    if @major != rhs.major
      false
    elsif !@minor or !rhs.minor
      true
    else
      @minor == rhs.minor
    end
  end
end

MappingRegistry.set(
  ::RAA::Category,
  ::SOAP::SOAPStruct,
  ::SOAP::Mapping::Registry::TypedStructFactory,
  { :type => XSD::QName.new(InterfaceNS, "Category") }
)

class Product
  include SOAP::Marshallable

  @@schema_type = 'Product'
  @@schema_ns = InterfaceNS

  attr_reader :id, :name
  attr_accessor :short_description, :version, :status, :homepage, :download, :license, :description

  def initialize(name, short_description = nil, version = nil, status = nil, homepage = nil, download = nil, license = nil, description = nil)
    @name = name
    @short_description = short_description
    @version = version
    @status = status
    @homepage = homepage
    @download = download
    @license = license
    @description = description
  end
end

MappingRegistry.set(
  ::RAA::Product,
  ::SOAP::SOAPStruct,
  ::SOAP::Mapping::Registry::TypedStructFactory,
  { :type => XSD::QName.new(InterfaceNS, "Product") }
)

class Owner
  include SOAP::Marshallable

  @@schema_type = 'Owner'
  @@schema_ns = InterfaceNS

  attr_reader :id
  attr_accessor :email, :name

  def initialize(email, name)
    @email = email
    @name = name
    @id = "#{ @email }-#{ @name }"
  end
end

MappingRegistry.set(
  ::RAA::Owner,
  ::SOAP::SOAPStruct,
  ::SOAP::Mapping::Registry::TypedStructFactory,
  { :type => XSD::QName.new(InterfaceNS, "Owner") }
)

class Info
  include SOAP::Marshallable

  @@schema_type = 'Info'
  @@schema_ns = InterfaceNS

  attr_accessor :category, :product, :owner, :updated, :created

  def initialize(category = nil, product = nil, owner = nil, updated = nil, created = nil)
    @category = category
    @product = product
    @owner = owner
    @updated = updated
    @created = created
  end

  def <=>(rhs)
    @updated <=> rhs.updated
  end

  def eql?(rhs)
    @product.name == rhs.product.name
  end
end

MappingRegistry.set(
  ::RAA::Info,
  ::SOAP::SOAPStruct,
  ::SOAP::Mapping::Registry::TypedStructFactory,
  { :type => XSD::QName.new(InterfaceNS, "Info") }
)

class StringArray < Array; end
MappingRegistry.set(
  ::RAA::StringArray,
  ::SOAP::SOAPArray,
  ::SOAP::Mapping::Registry::TypedArrayFactory,
  { :type => XSD::XSDString::Type }
)

class InfoArray < Array; end
MappingRegistry.set(
  ::RAA::InfoArray,
  ::SOAP::SOAPArray,
  ::SOAP::Mapping::Registry::TypedArrayFactory,
  { :type => XSD::QName.new(InterfaceNS, 'Info') }
)


end
