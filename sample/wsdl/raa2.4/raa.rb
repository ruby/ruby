# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class Gem
  @@schema_type = "Gem"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"

  def id
    @id
  end

  def id=(value)
    @id = value
  end

  def category
    @category
  end

  def category=(value)
    @category = value
  end

  def owner
    @owner
  end

  def owner=(value)
    @owner = value
  end

  def project
    @project
  end

  def project=(value)
    @project = value
  end

  def updated
    @updated
  end

  def updated=(value)
    @updated = value
  end

  def created
    @created
  end

  def created=(value)
    @created = value
  end

  def initialize(id = nil,
      category = nil,
      owner = nil,
      project = nil,
      updated = nil,
      created = nil)
    @id = id
    @category = category
    @owner = owner
    @project = project
    @updated = updated
    @created = created
  end
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class Category
  @@schema_type = "Category"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"

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

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class Owner
  @@schema_type = "Owner"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"

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

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class Project
  @@schema_type = "Project"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"

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

  def url
    @url
  end

  def url=(value)
    @url = value
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

  def updated
    @updated
  end

  def updated=(value)
    @updated = value
  end

  def history
    @history
  end

  def history=(value)
    @history = value
  end

  def dependency
    @dependency
  end

  def dependency=(value)
    @dependency = value
  end

  def initialize(name = nil,
      short_description = nil,
      version = nil,
      status = nil,
      url = nil,
      download = nil,
      license = nil,
      description = nil,
      updated = nil,
      history = nil,
      dependency = nil)
    @name = name
    @short_description = short_description
    @version = version
    @status = status
    @url = url
    @download = download
    @license = license
    @description = description
    @updated = updated
    @history = history
    @dependency = dependency
  end
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class ProjectDependency
  @@schema_type = "ProjectDependency"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"

  def project
    @project
  end

  def project=(value)
    @project = value
  end

  def version
    @version
  end

  def version=(value)
    @version = value
  end

  def description
    @description
  end

  def description=(value)
    @description = value
  end

  def initialize(project = nil,
      version = nil,
      description = nil)
    @project = project
    @version = version
    @description = description
  end
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class GemArray < Array
  # Contents type should be dumped here...
  @@schema_type = "GemArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class OwnerArray < Array
  # Contents type should be dumped here...
  @@schema_type = "OwnerArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class ProjectArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ProjectArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class ProjectDependencyArray < Array
  # Contents type should be dumped here...
  @@schema_type = "ProjectDependencyArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"
end

# http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/
class StringArray < Array
  # Contents type should be dumped here...
  @@schema_type = "StringArray"
  @@schema_ns = "http://www.ruby-lang.org/xmlns/soap/type/RAA/0.0.3/"
end

# http://xml.apache.org/xml-soap
class Map < Array
  # Contents type should be dumped here...
  @@schema_type = "Map"
  @@schema_ns = "http://xml.apache.org/xml-soap"
end

