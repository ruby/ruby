require 'rdoc/context'

##
# A TopLevel context is a representation of the contents of a single file

class RDoc::TopLevel < RDoc::Context

  ##
  # This TopLevel's File::Stat struct

  attr_accessor :file_stat

  ##
  # Relative name of this file

  attr_accessor :relative_name

  ##
  # Absolute name of this file

  attr_accessor :absolute_name

  attr_accessor :diagram

  ##
  # The parser that processed this file

  attr_accessor :parser

  ##
  # Returns all classes and modules discovered by RDoc

  def self.all_classes_and_modules
    classes_hash.values + modules_hash.values
  end

  ##
  # Returns all classes discovered by RDoc

  def self.classes
    classes_hash.values
  end

  ##
  # Hash of all classes known to RDoc

  def self.classes_hash
    @all_classes
  end

  ##
  # All TopLevels known to RDoc

  def self.files
    @all_files.values
  end

  ##
  # Hash of all files known to RDoc

  def self.files_hash
    @all_files
  end

  ##
  # Finds the class with +name+ in all discovered classes

  def self.find_class_named(name)
    classes_hash[name]
  end

  ##
  # Finds the class with +name+ starting in namespace +from+

  def self.find_class_named_from name, from
    from = find_class_named from unless RDoc::Context === from

    until RDoc::TopLevel === from do
      return nil unless from

      klass = from.find_class_named name
      return klass if klass

      from = from.parent
    end

    find_class_named name
  end

  ##
  # Finds the class or module with +name+

  def self.find_class_or_module(name)
    name =~ /^::/
    name = $' || name

    RDoc::TopLevel.classes_hash[name] || RDoc::TopLevel.modules_hash[name]
  end

  ##
  # Finds the file with +name+ in all discovered files

  def self.find_file_named(name)
    @all_files[name]
  end

  ##
  # Finds the module with +name+ in all discovered modules

  def self.find_module_named(name)
    modules_hash[name]
  end

  ##
  # Returns all modules discovered by RDoc

  def self.modules
    modules_hash.values
  end

  ##
  # Hash of all modules known to RDoc

  def self.modules_hash
    @all_modules
  end

  ##
  # Empties RDoc of stored class, module and file information

  def self.reset
    @all_classes = {}
    @all_modules = {}
    @all_files   = {}
  end

  reset

  ##
  # Creates a new TopLevel for +file_name+

  def initialize(file_name)
    super()
    @name = nil
    @relative_name = file_name
    @absolute_name = file_name
    @file_stat     = File.stat(file_name) rescue nil # HACK for testing
    @diagram       = nil
    @parser        = nil

    RDoc::TopLevel.files_hash[file_name] = self
  end

  ##
  # Adds +method+ to Object instead of RDoc::TopLevel

  def add_method(method)
    object = self.class.find_class_named 'Object'
    object = add_class RDoc::NormalClass, 'Object' unless object

    object.add_method method
  end

  ##
  # Base name of this file

  def base_name
    File.basename @absolute_name
  end

  ##
  # See RDoc::TopLevel.find_class_or_module

  def find_class_or_module name
    RDoc::TopLevel.find_class_or_module name
  end

  ##
  # Finds a class or module named +symbol+

  def find_local_symbol(symbol)
    find_class_or_module(symbol) || super
  end

  ##
  # Finds a module or class with +name+

  def find_module_named(name)
    find_class_or_module(name) || find_enclosing_module_named(name)
  end

  ##
  # The name of this file

  def full_name
    @relative_name
  end

  ##
  # URL for this with a +prefix+

  def http_url(prefix)
    path = [prefix, @relative_name.tr('.', '_')]

    File.join(*path.compact) + '.html'
  end

  def inspect # :nodoc:
    "#<%s:0x%x %p modules: %p classes: %p>" % [
      self.class, object_id,
      base_name,
      @modules.map { |n,m| m },
      @classes.map { |n,c| c }
    ]
  end

  ##
  # Date this file was last modified, if known

  def last_modified
    @file_stat ? file_stat.mtime.to_s : 'Unknown'
  end

  ##
  # Base name of this file

  alias name base_name

  ##
  # Path to this file

  def path
    http_url RDoc::RDoc.current.generator.file_dir
  end

  def pretty_print q # :nodoc:
    q.group 2, "[#{self.class}: ", "]" do
      q.text "base name: #{base_name.inspect}"
      q.breakable

      items = @modules.map { |n,m| m }
      items.push(*@modules.map { |n,c| c })
      q.seplist items do |mod| q.pp mod end
    end
  end

end

