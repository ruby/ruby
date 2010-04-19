require 'rdoc/code_object'

##
# A Context is something that can hold modules, classes, methods, attributes,
# aliases, requires, and includes. Classes, modules, and files are all
# Contexts.

class RDoc::Context < RDoc::CodeObject

  include Comparable

  ##
  # Types of methods

  TYPES = %w[class instance]

  ##
  # Method visibilities

  VISIBILITIES = [:public, :protected, :private]

  ##
  # Aliased methods

  attr_reader :aliases

  ##
  # attr* methods

  attr_reader :attributes

  ##
  # Constants defined

  attr_reader :constants

  ##
  # Current section of documentation

  attr_reader :current_section

  ##
  # Files this context is found in

  attr_reader :in_files

  ##
  # Modules this context includes

  attr_reader :includes

  ##
  # Methods defined in this context

  attr_reader :method_list

  ##
  # Name of this class excluding namespace.  See also full_name

  attr_reader :name

  ##
  # Files this context requires

  attr_reader :requires

  ##
  # Sections in this context

  attr_reader :sections

  ##
  # Aliases that haven't been resolved to a method

  attr_accessor :unmatched_alias_lists

  ##
  # Current visibility of this context

  attr_reader :visibility

  ##
  # A per-comment section of documentation like:
  #
  #   # :SECTION: The title
  #   # The body

  class Section

    ##
    # Section comment

    attr_reader :comment

    ##
    # Context this Section lives in

    attr_reader :parent

    ##
    # Section sequence number (for linking)

    attr_reader :sequence

    ##
    # Section title

    attr_reader :title

    @@sequence = "SEC00000"

    ##
    # Creates a new section with +title+ and +comment+

    def initialize(parent, title, comment)
      @parent = parent
      @title = title

      @@sequence.succ!
      @sequence = @@sequence.dup

      set_comment comment
    end

    ##
    # Sections are equal when they have the same #sequence

    def ==(other)
      self.class === other and @sequence == other.sequence
    end

    def inspect # :nodoc:
      "#<%s:0x%x %s %p>" % [
        self.class, object_id,
        @sequence, title
      ]
    end

    ##
    # Set the comment for this section from the original comment block If
    # the first line contains :section:, strip it and use the rest.
    # Otherwise remove lines up to the line containing :section:, and look
    # for those lines again at the end and remove them. This lets us write
    #
    #   # blah blah blah
    #   #
    #   # :SECTION: The title
    #   # The body

    def set_comment(comment)
      return unless comment

      if comment =~ /^#[ \t]*:section:.*\n/ then
        start = $`
        rest = $'

        if start.empty?
          @comment = rest
        else
          @comment = rest.sub(/#{start.chomp}\Z/, '')
        end
      else
        @comment = comment
      end

      @comment = nil if @comment.empty?
    end

  end

  ##
  # Creates an unnamed empty context with public visibility

  def initialize
    super

    @in_files = []

    @name    ||= "unknown"
    @comment ||= ""
    @parent  = nil
    @visibility = :public

    @current_section = Section.new self, nil, nil
    @sections = [@current_section]

    initialize_methods_etc
    initialize_classes_and_modules
  end

  ##
  # Sets the defaults for classes and modules

  def initialize_classes_and_modules
    @classes = {}
    @modules = {}
  end

  ##
  # Sets the defaults for methods and so-forth

  def initialize_methods_etc
    @method_list = []
    @attributes  = []
    @aliases     = []
    @requires    = []
    @includes    = []
    @constants   = []

    # This Hash maps a method name to a list of unmatched aliases (aliases of
    # a method not yet encountered).
    @unmatched_alias_lists = {}
  end

  ##
  # Contexts are sorted by full_name

  def <=>(other)
    full_name <=> other.full_name
  end

  ##
  # Adds +an_alias+ that is automatically resolved

  def add_alias(an_alias)
    meth = find_instance_method_named(an_alias.old_name)

    if meth then
      add_alias_impl an_alias, meth
    else
      add_to @aliases, an_alias
      unmatched_alias_list = @unmatched_alias_lists[an_alias.old_name] ||= []
      unmatched_alias_list.push an_alias
    end

    an_alias
  end

  ##
  # Turns +an_alias+ into an AnyMethod that points to +meth+

  def add_alias_impl(an_alias, meth)
    new_meth = RDoc::AnyMethod.new an_alias.text, an_alias.new_name
    new_meth.is_alias_for = meth
    new_meth.singleton    = meth.singleton
    new_meth.params       = meth.params

    new_meth.comment      = an_alias.comment

    meth.add_alias new_meth

    add_method new_meth

    # aliases don't use ongoing visibility
    new_meth.visibility = meth.visibility

    new_meth
  end

  ##
  # Adds +attribute+

  def add_attribute(attribute)
    add_to @attributes, attribute
  end

  ##
  # Adds a class named +name+ with +superclass+.
  #
  # Given <tt>class Container::Item</tt> RDoc assumes +Container+ is a module
  # unless it later sees <tt>class Container</tt>.  add_class automatically
  # upgrades +name+ to a class in this case.

  def add_class(class_type, name, superclass = 'Object')
    klass = add_class_or_module @classes, class_type, name, superclass

    existing = klass.superclass
    existing = existing.name if existing and not String === existing

    if superclass != existing and superclass != 'Object' then
      klass.superclass = superclass
    end

    # If the parser encounters Container::Item before encountering
    # Container, then it assumes that Container is a module.  This may not
    # be the case, so remove Container from the module list if present and
    # transfer any contained classes and modules to the new class.

    mod = RDoc::TopLevel.modules_hash.delete klass.full_name

    if mod then
      klass.classes_hash.update mod.classes_hash
      klass.modules_hash.update mod.modules_hash
      klass.method_list.concat mod.method_list

      @modules.delete klass.name
    end

    RDoc::TopLevel.classes_hash[klass.full_name] = klass

    klass
  end

  ##
  # Instantiates a +class_type+ named +name+ and adds it the modules or
  # classes Hash +collection+.

  def add_class_or_module(collection, class_type, name, superclass = nil)
    full_name = child_name name

    mod = collection[name]

    if mod then
      mod.superclass = superclass unless mod.module?
    else
      all = if class_type == RDoc::NormalModule then
              RDoc::TopLevel.modules_hash
            else
              RDoc::TopLevel.classes_hash
            end

      mod = all[full_name]

      unless mod then
        mod = class_type.new name, superclass
      else
        # If the class has been encountered already, check that its
        # superclass has been set (it may not have been, depending on the
        # context in which it was encountered).
        if class_type == RDoc::NormalClass then
          mod.superclass = superclass unless mod.superclass
        end
      end

      unless @done_documenting then
        all[full_name] = mod
        collection[name] = mod
      end

      mod.section = @current_section
      mod.parent = self
    end

    mod
  end

  ##
  # Adds +constant+

  def add_constant(constant)
    add_to @constants, constant
  end

  ##
  # Adds included module +include+

  def add_include(include)
    add_to @includes, include
  end

  ##
  # Adds +method+

  def add_method(method)
    method.visibility = @visibility
    add_to @method_list, method

    unmatched_alias_list = @unmatched_alias_lists[method.name]
    if unmatched_alias_list then
      unmatched_alias_list.each do |unmatched_alias|
        add_alias_impl unmatched_alias, method
        @aliases.delete unmatched_alias
      end

      @unmatched_alias_lists.delete method.name
    end
  end

  ##
  # Adds a module named +name+.  If RDoc already knows +name+ is a class then
  # that class is returned instead.  See also #add_class

  def add_module(class_type, name)
    return @classes[name] if @classes.key? name

    add_class_or_module @modules, class_type, name, nil
  end

  ##
  # Adds an alias from +from+ to +name+

  def add_module_alias from, name
    to_name = child_name name

    unless @done_documenting then
      if from.module? then
        RDoc::TopLevel.modules_hash
      else
        RDoc::TopLevel.classes_hash
      end[to_name] = from

      if from.module? then
        @modules
      else
        @classes
      end[name] = from
    end

    from
  end

  ##
  # Adds +require+ to this context's top level

  def add_require(require)
    if RDoc::TopLevel === self then
      add_to @requires, require
    else
      parent.add_require require
    end
  end

  ##
  # Adds +thing+ to the collection +array+

  def add_to(array, thing)
    array << thing if @document_self and not @done_documenting
    thing.parent = self
    thing.section = @current_section
  end

  ##
  # Creates the full name for a child with +name+

  def child_name name
    if RDoc::TopLevel === self then
      name
    else
      "#{self.full_name}::#{name}"
    end
  end

  ##
  # Array of classes in this context

  def classes
    @classes.values
  end

  ##
  # All classes and modules in this namespace

  def classes_and_modules
    classes + modules
  end

  ##
  # Hash of classes keyed by class name

  def classes_hash
    @classes
  end

  ##
  # Is part of this thing was defined in +file+?

  def defined_in?(file)
    @in_files.include?(file)
  end

  ##
  # Iterator for attributes

  def each_attribute # :yields: attribute
    @attributes.each { |a| yield a }
  end

  ##
  # Iterator for classes and modules

  def each_classmodule(&block) # :yields: module
    classes_and_modules.sort.each(&block)
  end

  ##
  # Iterator for constants

  def each_constant # :yields: constant
    @constants.each {|c| yield c}
  end

  ##
  # Iterator for included modules

  def each_include # :yields: include
    @includes.each do |i| yield i end
  end

  ##
  # Iterator for methods

  def each_method # :yields: method
    @method_list.sort.each {|m| yield m}
  end

  ##
  # Finds an attribute with +name+ in this context

  def find_attribute_named(name)
    @attributes.find { |m| m.name == name }
  end

  ##
  # Finds a class method with +name+ in this context

  def find_class_method_named(name)
    @method_list.find { |meth| meth.singleton && meth.name == name }
  end

  ##
  # Finds a constant with +name+ in this context

  def find_constant_named(name)
    @constants.find {|m| m.name == name}
  end

  ##
  # Find a module at a higher scope

  def find_enclosing_module_named(name)
    parent && parent.find_module_named(name)
  end

  ##
  # Finds a file with +name+ in this context

  def find_file_named(name)
    top_level.class.find_file_named(name)
  end

  ##
  # Finds an instance method with +name+ in this context

  def find_instance_method_named(name)
    @method_list.find { |meth| !meth.singleton && meth.name == name }
  end

  ##
  # Finds a method, constant, attribute, module or files named +symbol+ in
  # this context

  def find_local_symbol(symbol)
    find_method_named(symbol) or
    find_constant_named(symbol) or
    find_attribute_named(symbol) or
    find_module_named(symbol) or
    find_file_named(symbol)
  end

  ##
  # Finds a instance or module method with +name+ in this context

  def find_method_named(name)
    case name
    when /\A#/ then
      find_instance_method_named name[1..-1]
    when /\A::/ then
      find_class_method_named name[2..-1]
    else
      @method_list.find { |meth| meth.name == name }
    end
  end

  ##
  # Find a module with +name+ using ruby's scoping rules

  def find_module_named(name)
    res = @modules[name] || @classes[name]
    return res if res
    return self if self.name == name
    find_enclosing_module_named name
  end

  ##
  # Look up +symbol+.  If +method+ is non-nil, then we assume the symbol
  # references a module that contains that method.

  def find_symbol(symbol, method = nil)
    result = nil

    case symbol
    when /^::([A-Z].*)/ then
      result = top_level.find_symbol($1)
    when /::/ then
      modules = symbol.split(/::/)

      unless modules.empty? then
        module_name = modules.shift
        result = find_module_named(module_name)

        if result then
          modules.each do |name|
            result = result.find_module_named name
            break unless result
          end
        end
      end
    end

    unless result then
      # if a method is specified, then we're definitely looking for
      # a module, otherwise it could be any symbol
      if method then
        result = find_module_named symbol
      else
        result = find_local_symbol symbol
        if result.nil? then
          if symbol =~ /^[A-Z]/ then
            result = parent
            while result && result.name != symbol do
              result = result.parent
            end
          end
        end
      end
    end

    result = result.find_local_symbol method if result and method

    result
  end

  ##
  # The full name for this context.  This method is overridden by subclasses.

  def full_name
    '(unknown)'
  end

  ##
  # URL for this with a +prefix+

  def http_url(prefix)
    path = full_name
    path = path.gsub(/<<\s*(\w*)/, 'from-\1') if path =~ /<</
    path = [prefix] + path.split('::')

    File.join(*path.compact) + '.html'
  end

  ##
  # Breaks method_list into a nested hash by type (class or instance) and
  # visibility (public, protected private)

  def methods_by_type
    methods = {}

    TYPES.each do |type|
      visibilities = {}
      VISIBILITIES.each do |vis|
        visibilities[vis] = []
      end

      methods[type] = visibilities
    end

    each_method do |method|
      methods[method.type][method.visibility] << method
    end

    methods
  end

  ##
  # Yields Method and Attr entries matching the list of names in +methods+.
  # Attributes are only returned when +singleton+ is false.

  def methods_matching(methods, singleton = false)
    count = 0

    @method_list.each do |m|
      if methods.include? m.name and m.singleton == singleton then
        yield m
        count += 1
      end
    end

    return if count == methods.size || singleton

    @attributes.each do |a|
      yield a if methods.include? a.name
    end
  end

  ##
  # Array of modules in this context

  def modules
    @modules.values
  end

  ##
  # Hash of modules keyed by module name

  def modules_hash
    @modules
  end

  ##
  # Changes the visibility for new methods to +visibility+

  def ongoing_visibility=(visibility)
    @visibility = visibility
  end

  ##
  # Record which file +top_level+ is in

  def record_location(top_level)
    @in_files << top_level unless @in_files.include?(top_level)
  end

  ##
  # If a class's documentation is turned off after we've started collecting
  # methods etc., we need to remove the ones we have

  def remove_methods_etc
    initialize_methods_etc
  end

  ##
  # Given an array +methods+ of method names, set the visibility of each to
  # +visibility+

  def set_visibility_for(methods, visibility, singleton = false)
    methods_matching methods, singleton do |m|
      m.visibility = visibility
    end
  end

  ##
  # Removes classes and modules when we see a :nodoc: all

  def remove_classes_and_modules
    initialize_classes_and_modules
  end

  ##
  # Creates a new section with +title+ and +comment+

  def set_current_section(title, comment)
    @current_section = Section.new self, title, comment
    @sections << @current_section
  end

  ##
  # Return the TopLevel that owns us

  def top_level
    return @top_level if defined? @top_level
    @top_level = self
    @top_level = @top_level.parent until RDoc::TopLevel === @top_level
    @top_level
  end

end

