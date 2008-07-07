# http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/
class Category
  @@schema_type = "Category"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"

  def major
    @major
  end

  def major=(value)
    @major = value
  end

  def minor
    @minor
  end

  def minor=(value)
    @minor = value
  end

  def initialize(major = nil,
      minor = nil)
    @major = major
    @minor = minor
  end
end

# http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/
class Product
  @@schema_type = "Product"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"

  def id
    @id
  end

  def id=(value)
    @id = value
  end

  def name
    @name
  end

  def name=(value)
    @name = value
  end

  def short_description
    @short_description
  end

  def short_description=(value)
    @short_description = value
  end

  def version
    @version
  end

  def version=(value)
    @version = value
  end

  def status
    @status
  end

  def status=(value)
    @status = value
  end

  def homepage
    @homepage
  end

  def homepage=(value)
    @homepage = value
  end

  def download
    @download
  end

  def download=(value)
    @download = value
  end

  def license
    @license
  end

  def license=(value)
    @license = value
  end

  def description
    @description
  end

  def description=(value)
    @description = value
  end

  def initialize(id = nil,
      name = nil,
      short_description = nil,
      version = nil,
      status = nil,
      homepage = nil,
      download = nil,
      license = nil,
      description = nil)
    @id = id
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

# http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/
class Owner
  @@schema_type = "Owner"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"

  def id
    @id
  end

  def id=(value)
    @id = value
  end

  def email
    @email
  end

  def email=(value)
    @email = value
  end

  def name
    @name
  end

  def name=(value)
    @name = value
  end

  def initialize(id = nil,
      email = nil,
      name = nil)
    @id = id
    @email = email
    @name = name
  end
end

# http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/
class Info
  @@schema_type = "Info"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"

  def category
    @category
  end

  def category=(value)
    @category = value
  end

  def product
    @product
  end

  def product=(value)
    @product = value
  end

  def owner
    @owner
  end

  def owner=(value)
    @owner = value
  end

  def created
    @created
  end

  def created=(value)
    @created = value
  end

  def updated
    @updated
  end

  def updated=(value)
    @updated = value
  end

  def initialize(category = nil,
      product = nil,
      owner = nil,
      created = nil,
      updated = nil)
    @category = category
    @product = product
    @owner = owner
    @created = created
    @updated = updated
  end
end

# http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/
class InfoArray < Array
  # Contents type should be dumped here...
  @@schema_type = "InfoArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"
end

# http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/
class StringArray < Array
  # Contents type should be dumped here...
  @@schema_type = "StringArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/interface/RAA/0.0.2/"
end

# http://xml.apache.org/xml-soap
class Map < Array
  # Contents type should be dumped here...
  @@schema_type = "Map"
  @@schema_ns = "http://xml.apache.org/xml-soap"
end

