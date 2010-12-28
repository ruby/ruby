require 'rdoc/context'

##
# ClassModule is the base class for objects representing either a class or a
# module.

class RDoc::ClassModule < RDoc::Context

  MARSHAL_VERSION = 0 # :nodoc:

  ##
  # Constants that are aliases for this class or module

  attr_accessor :constant_aliases

  attr_accessor :diagram # :nodoc:

  ##
  # Class or module this constant is an alias for

  attr_accessor :is_alias_for

  ##
  # Return a RDoc::ClassModule of class +class_type+ that is a copy
  # of module +module+. Used to promote modules to classes.

  def self.from_module(class_type, mod)
    klass = class_type.new(mod.name)
    klass.comment = mod.comment
    klass.parent = mod.parent
    klass.section = mod.section
    klass.viewer = mod.viewer

    klass.attributes.concat mod.attributes
    klass.method_list.concat mod.method_list
    klass.aliases.concat mod.aliases
    klass.external_aliases.concat mod.external_aliases
    klass.constants.concat mod.constants
    klass.includes.concat mod.includes

    klass.methods_hash.update mod.methods_hash
    klass.constants_hash.update mod.constants_hash

    klass.current_section = mod.current_section
    klass.in_files.concat mod.in_files
    klass.sections.concat mod.sections
    klass.unmatched_alias_lists = mod.unmatched_alias_lists
    klass.current_section = mod.current_section
    klass.visibility = mod.visibility

    klass.classes_hash.update mod.classes_hash
    klass.modules_hash.update mod.modules_hash
    klass.metadata.update mod.metadata

    klass.document_self = mod.received_nodoc ? nil : mod.document_self
    klass.document_children = mod.document_children
    klass.force_documentation = mod.force_documentation
    klass.done_documenting = mod.done_documenting

    # update the parent of all children

    (klass.attributes +
     klass.method_list +
     klass.aliases +
     klass.external_aliases +
     klass.constants +
     klass.includes +
     klass.classes +
     klass.modules).each do |obj|
      obj.parent = klass
      obj.full_name = nil
    end

    klass
  end

  ##
  # Creates a new ClassModule with +name+ with optional +superclass+
  #
  # This is a constructor for subclasses, and must never be called directly.

  def initialize(name, superclass = nil)
    @constant_aliases = []
    @diagram          = nil
    @is_alias_for     = nil
    @name             = name
    @superclass       = superclass
    super()
  end

  ##
  # Ancestors list for this ClassModule: the list of included modules
  # (classes will add their superclass if any).
  #
  # Returns the included classes or modules, not the includes
  # themselves. The returned values are either String or
  # RDoc::NormalModule instances (see RDoc::Include#module).
  #
  # The values are returned in reverse order of their inclusion,
  # which is the order suitable for searching methods/attributes
  # in the ancestors. The superclass, if any, comes last.

  def ancestors
    includes.map { |i| i.module }.reverse
  end

  ##
  # Clears the comment. Used by the ruby parser.

  def clear_comment
    @comment = ''
  end

  ##
  # Appends +comment+ to the current comment, but separated by a rule.  Works
  # more like <tt>+=</tt>.

  def comment= comment
    return if comment.empty?

    comment = normalize_comment comment
    comment = "#{@comment}\n---\n#{comment}" unless
      @comment.empty?

    super
  end

  ##
  # Prepares this ClassModule for use by a generator.
  #
  # See RDoc::TopLevel::complete

  def complete min_visibility
    update_aliases
    remove_nodoc_children
    update_includes
    remove_invisible min_visibility
  end

  ##
  # Looks for a symbol in the #ancestors. See Context#find_local_symbol.

  def find_ancestor_local_symbol symbol
    ancestors.each do |m|
      next if m.is_a?(String)
      res = m.find_local_symbol(symbol)
      return res if res
    end

    nil
  end

  ##
  # Finds a class or module with +name+ in this namespace or its descendents

  def find_class_named name
    return self if full_name == name
    return self if @name == name

    @classes.values.find do |klass|
      next if klass == self
      klass.find_class_named name
    end
  end

  ##
  # Return the fully qualified name of this class or module

  def full_name
    @full_name ||= if RDoc::ClassModule === @parent then
                     "#{@parent.full_name}::#{@name}"
                   else
                     @name
                   end
  end

  def marshal_dump # :nodoc:
    # TODO must store the singleton attribute
    attrs = attributes.sort.map do |attr|
      [attr.name, attr.rw]
    end

    method_types = methods_by_type.map do |type, visibilities|
      visibilities = visibilities.map do |visibility, methods|
        method_names = methods.map do |method|
          method.name
        end

        [visibility, method_names.uniq]
      end

      [type, visibilities]
    end

    [ MARSHAL_VERSION,
      @name,
      full_name,
      @superclass,
      parse(@comment),
      attrs,
      constants.map do |const|
        [const.name, parse(const.comment)]
      end,
      includes.map do |incl|
        [incl.name, parse(incl.comment)]
      end,
      method_types,
    ]
  end

  def marshal_load array # :nodoc:
    # TODO must restore the singleton attribute
    initialize_methods_etc
    @document_self    = true
    @done_documenting = false
    @current_section  = nil
    @parent           = nil
    @visibility       = nil

    @name       = array[1]
    @full_name  = array[2]
    @superclass = array[3]
    @comment    = array[4]

    array[5].each do |name, rw|
      add_attribute RDoc::Attr.new(nil, name, rw, nil)
    end

    array[6].each do |name, comment|
      add_constant RDoc::Constant.new(name, nil, comment)
    end

    array[7].each do |name, comment|
      add_include RDoc::Include.new(name, comment)
    end

    array[8].each do |type, visibilities|
      visibilities.each do |visibility, methods|
        @visibility = visibility

        methods.each do |name|
          method = RDoc::AnyMethod.new nil, name
          method.singleton = true if type == 'class'
          add_method method
        end
      end
    end
  end

  ##
  # Merges +class_module+ into this ClassModule

  def merge class_module
    comment = class_module.comment

    if comment then
      document = parse @comment

      comment.parts.concat document.parts

      @comment = comment
    end

    class_module.each_attribute do |attr|
      if match = attributes.find { |a| a.name == attr.name } then
        match.rw = [match.rw, attr.rw].compact.join
      else
        add_attribute attr
      end
    end

    class_module.each_constant do |const|
      add_constant const
    end

    class_module.each_include do |incl|
      add_include incl
    end

    class_module.each_method do |meth|
      add_method meth
    end
  end

  ##
  # Does this object represent a module?

  def module?
    false
  end

  ##
  # Allows overriding the initial name.
  #
  # Used for modules and classes that are constant aliases.

  def name= new_name
    @name = new_name
  end

  ##
  # Path to this class or module

  def path
    http_url RDoc::RDoc.current.generator.class_dir
  end

  ##
  # Name to use to generate the url:
  # modules and classes that are aliases for another
  # module or classe return the name of the latter.

  def name_for_path
    is_alias_for ? is_alias_for.full_name : full_name
  end

  ##
  # Returns the classes and modules that are not constants
  # aliasing another class or module. For use by formatters
  # only (caches its result).

  def non_aliases
    @non_aliases ||= classes_and_modules.reject { |cm| cm.is_alias_for }
  end

  ##
  # Updates the child modules or classes of class/module +parent+ by
  # deleting the ones that have been removed from the documentation.
  #
  # +parent_hash+ is either <tt>parent.modules_hash</tt> or
  # <tt>parent.classes_hash</tt> and +all_hash+ is ::all_modules_hash or
  # ::all_classes_hash.

  def remove_nodoc_children
    prefix = self.full_name + '::'

    modules_hash.each_key do |name|
      full_name = prefix + name
      modules_hash.delete name unless RDoc::TopLevel.all_modules_hash[full_name]
    end

    classes_hash.each_key do |name|
      full_name = prefix + name
      classes_hash.delete name unless RDoc::TopLevel.all_classes_hash[full_name]
    end
  end

  ##
  # Get the superclass of this class.  Attempts to retrieve the superclass
  # object, returns the name if it is not known.

  def superclass
    RDoc::TopLevel.find_class_named(@superclass) || @superclass
  end

  ##
  # Set the superclass of this class to +superclass+

  def superclass=(superclass)
    raise NoMethodError, "#{full_name} is a module" if module?
    @superclass = superclass
  end

  def to_s # :nodoc:
    if is_alias_for then
      "#{self.class.name} #{self.full_name} -> #{is_alias_for}"
    else
      super
    end
  end

  ##
  # 'module' or 'class'

  def type
    module? ? 'module' : 'class'
  end

  ##
  # Updates the child modules & classes by replacing the ones that are
  # aliases through a constant.
  #
  # The aliased module/class is replaced in the children and in
  # RDoc::TopLevel::all_modules_hash or RDoc::TopLevel::all_classes_hash
  # by a copy that has <tt>RDoc::ClassModule#is_alias_for</tt> set to
  # the aliased module/class, and this copy is added to <tt>#aliases</tt>
  # of the aliased module/class.
  #
  # Formatters can use the #non_aliases method to retrieve children that
  # are not aliases, for instance to list the namespace content, since
  # the aliased modules are included in the constants of the class/module,
  # that are listed separately.

  def update_aliases
    constants.each do |const|
      next unless cm = const.is_alias_for
      cm_alias = cm.dup
      cm_alias.name = const.name
      cm_alias.parent = self
      cm_alias.full_name = nil  # force update for new parent
      cm_alias.aliases.clear
      cm_alias.is_alias_for = cm

      if cm.module? then
        RDoc::TopLevel.all_modules_hash[cm_alias.full_name] = cm_alias
        modules_hash[const.name] = cm_alias
      else
        RDoc::TopLevel.all_classes_hash[cm_alias.full_name] = cm_alias
        classes_hash[const.name] = cm_alias
      end

      cm.aliases << cm_alias
    end
  end

  ##
  # Deletes from #includes those whose module has been removed from the
  # documentation.
  #--
  # FIXME: includes are not reliably removed, see _possible_bug test case

  def update_includes
    includes.reject! do |include|
      mod = include.module
      !(String === mod) && RDoc::TopLevel.all_modules_hash[mod.full_name].nil?
    end
  end

end

