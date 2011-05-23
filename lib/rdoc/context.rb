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
  # Class/module aliases

  attr_reader :aliases

  ##
  # All attr* methods

  attr_reader :attributes

  ##
  # Constants defined

  attr_reader :constants

  ##
  # Current section of documentation

  attr_accessor :current_section

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
  # Hash <tt>old_name => [aliases]</tt>, for aliases
  # that haven't (yet) been resolved to a method/attribute.
  # (Not to be confused with the aliases of the context.)

  attr_accessor :unmatched_alias_lists

  ##
  # Aliases that could not eventually be resolved.

  attr_reader :external_aliases

  ##
  # Current visibility of this context

  attr_accessor :visibility

  ##
  # Hash of registered methods. Attributes are also registered here,
  # twice if they are RW.

  attr_reader :methods_hash

  ##
  # Hash of registered constants.

  attr_reader :constants_hash

  ##
  # A section of documentation like:
  #
  #   # :section: The title
  #   # The body
  #
  # Sections can be referenced multiple times and will be collapsed into a
  # single section.

  class Section

    include RDoc::Text

    ##
    # Section comment

    attr_reader :comment

    ##
    # Context this Section lives in

    attr_reader :parent

    ##
    # Section title

    attr_reader :title

    @@sequence = "SEC00000"

    ##
    # Creates a new section with +title+ and +comment+

    def initialize parent, title, comment
      @parent = parent
      @title = title ? title.strip : title

      @@sequence.succ!
      @sequence = @@sequence.dup

      @comment = extract_comment comment
    end

    ##
    # Sections are equal when they have the same #title

    def == other
      self.class === other and @title == other.title
    end

    ##
    # Anchor reference for linking to this section

    def aref
      title = @title || '[untitled]'

      CGI.escape(title).gsub('%', '-').sub(/^-/, '')
    end

    ##
    # Appends +comment+ to the current comment separated by a rule.

    def comment= comment
      comment = extract_comment comment

      return if comment.empty?

      if @comment then
        @comment += "\n# ---\n#{comment}"
      else
        @comment = comment
      end
    end

    ##
    # Extracts the comment for this section from the original comment block.
    # If the first line contains :section:, strip it and use the rest.
    # Otherwise remove lines up to the line containing :section:, and look
    # for those lines again at the end and remove them. This lets us write
    #
    #   # :section: The title
    #   # The body

    def extract_comment comment
      if comment =~ /^#[ \t]*:section:.*\n/ then
        start = $`
        rest = $'

        if start.empty? then
          rest
        else
          rest.sub(/#{start.chomp}\Z/, '')
        end
      else
        comment
      end
    end

    def inspect # :nodoc:
      "#<%s:0x%x %s %p>" % [
        self.class, object_id,
        @sequence, title
      ]
    end

    ##
    # Section sequence number (deprecated)

    def sequence
      warn "RDoc::Context::Section#sequence is deprecated, use #aref"
      @sequence
    end

  end

  ##
  # Creates an unnamed empty context with public current visibility

  def initialize
    super

    @in_files = []

    @name    ||= "unknown"
    @parent  = nil
    @visibility = :public

    @current_section = Section.new self, nil, nil
    @sections = { nil => @current_section }

    @classes = {}
    @modules = {}

    initialize_methods_etc
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
    @external_aliases = []

    # This Hash maps a method name to a list of unmatched aliases (aliases of
    # a method not yet encountered).
    @unmatched_alias_lists = {}

    @methods_hash = {}
    @constants_hash = {}
  end

  ##
  # Contexts are sorted by full_name

  def <=>(other)
    full_name <=> other.full_name
  end

  ##
  # Adds +an_alias+ that is automatically resolved

  def add_alias an_alias
    return an_alias unless @document_self

    method_attr = find_method(an_alias.old_name, an_alias.singleton) ||
                  find_attribute(an_alias.old_name, an_alias.singleton)

    if method_attr then
      method_attr.add_alias an_alias, self
    else
      add_to @external_aliases, an_alias
      unmatched_alias_list =
        @unmatched_alias_lists[an_alias.pretty_old_name] ||= []
      unmatched_alias_list.push an_alias
    end

    an_alias
  end

  ##
  # Adds +attribute+ if not already there. If it is (as method(s) or attribute),
  # updates the comment if it was empty.
  #
  # The attribute is registered only if it defines a new method.
  # For instance, <tt>attr_reader :foo</tt> will not be registered
  # if method +foo+ exists, but <tt>attr_accessor :foo</tt> will be registered
  # if method +foo+ exists, but <tt>foo=</tt> does not.

  def add_attribute attribute
    return attribute unless @document_self

    # mainly to check for redefinition of an attribute as a method
    # TODO find a policy for 'attr_reader :foo' + 'def foo=()'
    register = false

    if attribute.rw.index('R') then
      key = attribute.pretty_name
      known = @methods_hash[key]
      if known then
        known.comment = attribute.comment if known.comment.empty?
      else
        @methods_hash[key] = attribute
        register = true
      end
    end

    if attribute.rw.index('W')
      key = attribute.pretty_name << '='
      known = @methods_hash[key]
      if known then
        known.comment = attribute.comment if known.comment.empty?
      else
        @methods_hash[key] = attribute
        register = true
      end
    end

    if register then
      attribute.visibility = @visibility
      add_to @attributes, attribute
      resolve_aliases attribute
    end
  end

  ##
  # Adds a class named +given_name+ with +superclass+.
  #
  # Both +given_name+ and +superclass+ may contain '::', and are
  # interpreted relative to the +self+ context. This allows handling correctly
  # examples like these:
  #   class RDoc::Gauntlet < Gauntlet
  #   module Mod
  #     class Object   # implies < ::Object
  #     class SubObject < Object  # this is _not_ ::Object
  #
  # Given <tt>class Container::Item</tt> RDoc assumes +Container+ is a module
  # unless it later sees <tt>class Container</tt>.  +add_class+ automatically
  # upgrades +given_name+ to a class in this case.

  def add_class class_type, given_name, superclass = '::Object'
    # superclass +nil+ is passed by the C parser in the following cases:
    # - registering Object in 1.8 (correct)
    # - registering BasicObject in 1.9 (correct)
    # - registering RubyVM in 1.9 in iseq.c (incorrect: < Object in vm.c)
    #
    # If we later find a superclass for a registered class with a nil
    # superclass, we must honor it.

    # find the name & enclosing context
    if given_name =~ /^:+(\w+)$/ then
      full_name = $1
      enclosing = top_level
      name = full_name.split(/:+/).last
    else
      full_name = child_name given_name

      if full_name =~ /^(.+)::(\w+)$/ then
        name = $2
        ename = $1
        enclosing = RDoc::TopLevel.classes_hash[ename] ||
                    RDoc::TopLevel.modules_hash[ename]
        # HACK: crashes in actionpack/lib/action_view/helpers/form_helper.rb (metaprogramming)
        unless enclosing then
          # try the given name at top level (will work for the above example)
          enclosing = RDoc::TopLevel.classes_hash[given_name] || RDoc::TopLevel.modules_hash[given_name]
          return enclosing if enclosing
          # not found: create the parent(s)
          names = ename.split('::')
          enclosing = self
          names.each do |n|
            enclosing = enclosing.classes_hash[n] ||
                        enclosing.modules_hash[n] ||
                        enclosing.add_module(RDoc::NormalModule, n)
          end
        end
      else
        name = full_name
        enclosing = self
      end
    end

    # fix up superclass
    superclass = nil if full_name == 'BasicObject'
    superclass = nil if full_name == 'Object' and defined?(::BasicObject)
    superclass = '::BasicObject' if
      defined?(::BasicObject) and full_name == 'Object'

    # find the superclass full name
    if superclass then
      if superclass =~ /^:+/ then
        superclass = $' #'
      else
        if superclass =~ /^(\w+):+(.+)$/ then
          suffix = $2
          mod = find_module_named($1)
          superclass = mod.full_name + '::' + suffix if mod
        else
          mod = find_module_named(superclass)
          superclass = mod.full_name if mod
        end
      end

      # did we believe it was a module?
      mod = RDoc::TopLevel.modules_hash.delete superclass

      upgrade_to_class mod, RDoc::NormalClass, mod.parent if mod

      # e.g., Object < Object
      superclass = nil if superclass == full_name
    end

    klass = RDoc::TopLevel.classes_hash[full_name]

    if klass then
      # if TopLevel, it may not be registered in the classes:
      enclosing.classes_hash[name] = klass
      # update the superclass if needed
      if superclass then
        existing = klass.superclass
        existing = existing.full_name unless existing.is_a?(String) if existing
        if existing.nil? ||
           (existing == 'Object' && superclass != 'Object') then
          klass.superclass = superclass
        end
      end
    else
      # this is a new class
      mod = RDoc::TopLevel.modules_hash.delete full_name

      if mod then
        klass = upgrade_to_class mod, RDoc::NormalClass, enclosing

        klass.superclass = superclass unless superclass.nil?
      else
        klass = class_type.new name, superclass

        enclosing.add_class_or_module(klass, enclosing.classes_hash,
                                      RDoc::TopLevel.classes_hash)
      end
    end

    klass
  end

  ##
  # Adds the class or module +mod+ to the modules or
  # classes Hash +self_hash+, and to +all_hash+ (either
  # <tt>TopLevel::modules_hash</tt> or <tt>TopLevel::classes_hash</tt>),
  # unless #done_documenting is +true+. Sets the #parent of +mod+
  # to +self+, and its #section to #current_section. Returns +mod+.

  def add_class_or_module mod, self_hash, all_hash
    mod.section = @current_section # TODO declaring context? something is
                                   # wrong here...
    mod.parent = self

    unless @done_documenting then
      self_hash[mod.name] = mod
      # this must be done AFTER adding mod to its parent, so that the full
      # name is correct:
      all_hash[mod.full_name] = mod
    end

    mod
  end

  ##
  # Adds +constant+ if not already there. If it is, updates the comment,
  # value and/or is_alias_for of the known constant if they were empty/nil.

  def add_constant(constant)
    return constant unless @document_self

    # HACK: avoid duplicate 'PI' & 'E' in math.c (1.8.7 source code)
    # (this is a #ifdef: should be handled by the C parser)
    known = @constants_hash[constant.name]

    if known then
      known.comment = constant.comment if known.comment.empty?

      known.value = constant.value if
        known.value.nil? or known.value.strip.empty?

      known.is_alias_for ||= constant.is_alias_for
    else
      @constants_hash[constant.name] = constant
      add_to @constants, constant
    end
  end

  ##
  # Adds included module +include+ which should be an RDoc::Include

  def add_include(include)
    add_to @includes, include unless @includes.map { |i| i.full_name }.include?( include.full_name )
  end

  ##
  # Adds +method+ if not already there. If it is (as method or attribute),
  # updates the comment if it was empty.

  def add_method(method)
    return method unless @document_self

    # HACK: avoid duplicate 'new' in io.c & struct.c (1.8.7 source code)
    key = method.pretty_name
    known = @methods_hash[key]
    if known
      # TODO issue stderr messages if --verbose
      #$stderr.puts "\n#{display(method)} already registered as #{display(known)}"
      known.comment = method.comment if known.comment.empty?
    else
      @methods_hash[key] = method
      method.visibility = @visibility
      add_to @method_list, method
      resolve_aliases method
    end
  end

  ##
  # Adds a module named +name+.  If RDoc already knows +name+ is a class then
  # that class is returned instead.  See also #add_class.

  def add_module(class_type, name)
    mod = @classes[name] || @modules[name]
    return mod if mod

    full_name = child_name name
    mod = RDoc::TopLevel.modules_hash[full_name] || class_type.new(name)

    add_class_or_module(mod, @modules, RDoc::TopLevel.modules_hash)
  end

  ##
  # Adds an alias from +from+ (a class or module) to +name+ which was defined
  # in +file+.

  def add_module_alias from, name, file
    return from if @done_documenting

    to_name = child_name(name)

    # if we already know this name, don't register an alias:
    # see the metaprogramming in lib/active_support/basic_object.rb,
    # where we already know BasicObject as a class when we find
    # BasicObject = BlankSlate
    return from if RDoc::TopLevel.find_class_or_module(to_name)

    if from.module? then
      RDoc::TopLevel.modules_hash[to_name] = from
      @modules[name] = from
    else
      RDoc::TopLevel.classes_hash[to_name] = from
      @classes[name] = from
    end

    # HACK: register a constant for this alias:
    # constant value and comment will be updated after,
    # when the Ruby parser adds the constant
    const = RDoc::Constant.new name, nil, ''
    const.record_location file
    const.is_alias_for = from
    add_constant const

    from
  end

  ##
  # Adds +require+ to this context's top level

  def add_require(require)
    return require unless @document_self

    if RDoc::TopLevel === self then
      add_to @requires, require
    else
      parent.add_require require
    end
  end

  ##
  # Adds +thing+ to the collection +array+

  def add_to(array, thing)
    array << thing if @document_self
    thing.parent = self
    thing.section = @current_section
  end

  ##
  # Is there any content?
  # This means any of: comment, aliases, methods, attributes,
  # external aliases, require, constant.
  # Includes are also checked unless <tt>includes == false</tt>.

  def any_content(includes = true)
    @any_content ||= !(
      @comment.empty? &&
      @method_list.empty? &&
      @attributes.empty? &&
      @aliases.empty? &&
      @external_aliases.empty? &&
      @requires.empty? &&
      @constants.empty?
    )
    @any_content || (includes && !@includes.empty?)
  end

  ##
  # Creates the full name for a child with +name+

  def child_name name
    if name =~ /^:+/
      $'  #'
    elsif RDoc::TopLevel === self then
      name
    else
      "#{self.full_name}::#{name}"
    end
  end

  ##
  # Class attributes

  def class_attributes
    @class_attributes ||= attributes.select { |a| a.singleton }
  end

  ##
  # Class methods

  def class_method_list
    @class_method_list ||= method_list.select { |a| a.singleton }
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

  def display(method_attr) # :nodoc:
    if method_attr.is_a? RDoc::Attr
      "#{method_attr.definition} #{method_attr.pretty_name}"
    else
      "method #{method_attr.pretty_name}"
    end
  end

  ##
  # Iterator for ancestors for duck-typing.  Does nothing.  See
  # RDoc::ClassModule#each_ancestor.

  def each_ancestor # :nodoc:
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
  # Iterator for each section's contents sorted by title.  The +section+, the
  # section's +constants+ and the sections +attributes+ are yielded.  The
  # +constants+ and +attributes+ collections are sorted.
  #
  # To retrieve methods in a section use #methods_by_type with the optional
  # +section+ parameter.
  #
  # NOTE: Do not edit collections yielded by this method

  def each_section # :yields: section, constants, attributes
    constants  = @constants.group_by  do |constant|  constant.section end
    constants.default = []

    attributes = @attributes.group_by do |attribute| attribute.section end
    attributes.default = []

    @sections.sort_by { |title, _| title.to_s }.each do |_, section|
      yield section, constants[section].sort, attributes[section].sort
    end
  end

  ##
  # Finds an attribute +name+ with singleton value +singleton+.

  def find_attribute(name, singleton)
    name = $1 if name =~ /^(.*)=$/
    @attributes.find { |a| a.name == name && a.singleton == singleton }
  end

  ##
  # Finds an attribute with +name+ in this context

  def find_attribute_named(name)
    case name
    when /\A#/ then
      find_attribute name[1..-1], false
    when /\A::/ then
      find_attribute name[2..-1], true
    else
      @attributes.find { |a| a.name == name }
    end
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
  # Finds an external alias +name+ with singleton value +singleton+.

  def find_external_alias(name, singleton)
    @external_aliases.find { |m| m.name == name && m.singleton == singleton }
  end

  ##
  # Finds an external alias with +name+ in this context

  def find_external_alias_named(name)
    case name
    when /\A#/ then
      find_external_alias name[1..-1], false
    when /\A::/ then
      find_external_alias name[2..-1], true
    else
      @external_aliases.find { |a| a.name == name }
    end
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
  # Finds a method, constant, attribute, external alias, module or file
  # named +symbol+ in this context.

  def find_local_symbol(symbol)
    find_method_named(symbol) or
    find_constant_named(symbol) or
    find_attribute_named(symbol) or
    find_external_alias_named(symbol) or
    find_module_named(symbol) or
    find_file_named(symbol)
  end

  ##
  # Finds a method named +name+ with singleton value +singleton+.

  def find_method(name, singleton)
    @method_list.find { |m| m.name == name && m.singleton == singleton }
  end

  ##
  # Finds a instance or module method with +name+ in this context

  def find_method_named(name)
    case name
    when /\A#/ then
      find_method name[1..-1], false
    when /\A::/ then
      find_method name[2..-1], true
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
  # Look up +symbol+, first as a module, then as a local symbol.

  def find_symbol(symbol)
    find_symbol_module(symbol) || find_local_symbol(symbol)
  end

  ##
  # Look up a module named +symbol+.

  def find_symbol_module(symbol)
    result = nil

    # look for a class or module 'symbol'
    case symbol
    when /^::/ then
      result = RDoc::TopLevel.find_class_or_module(symbol)
    when /^(\w+):+(.+)$/
      suffix = $2
      top = $1
      searched = self
      loop do
        mod = searched.find_module_named(top)
        break unless mod
        result = RDoc::TopLevel.find_class_or_module(mod.full_name + '::' + suffix)
        break if result || searched.is_a?(RDoc::TopLevel)
        searched = searched.parent
      end
    else
      searched = self
      loop do
        result = searched.find_module_named(symbol)
        break if result || searched.is_a?(RDoc::TopLevel)
        searched = searched.parent
      end
    end

    result
  end

  ##
  # The full name for this context.  This method is overridden by subclasses.

  def full_name
    '(unknown)'
  end

  ##
  # Does this context and its methods and constants all have documentation?
  #
  # (Yes, fully documented doesn't mean everything.)

  def fully_documented?
    documented? and
      attributes.all? { |a| a.documented? } and
      method_list.all? { |m| m.documented? } and
      constants.all? { |c| c.documented? }
  end

  ##
  # URL for this with a +prefix+

  def http_url(prefix)
    path = name_for_path
    path = path.gsub(/<<\s*(\w*)/, 'from-\1') if path =~ /<</
    path = [prefix] + path.split('::')

    File.join(*path.compact) + '.html'
  end

  ##
  # Instance attributes

  def instance_attributes
    @instance_attributes ||= attributes.reject { |a| a.singleton }
  end

  ##
  # Instance methods

  def instance_method_list
    @instance_method_list ||= method_list.reject { |a| a.singleton }
  end

  ##
  # Breaks method_list into a nested hash by type (<tt>'class'</tt> or
  # <tt>'instance'</tt>) and visibility (+:public+, +:protected+, +:private+).
  #
  # If +section+ is provided only methods in that RDoc::Context::Section will
  # be returned.

  def methods_by_type section = nil
    methods = {}

    TYPES.each do |type|
      visibilities = {}
      RDoc::VISIBILITIES.each do |vis|
        visibilities[vis] = []
      end

      methods[type] = visibilities
    end

    each_method do |method|
      next if section and not method.section == section
      methods[method.type][method.visibility] << method
    end

    methods
  end

  ##
  # Yields AnyMethod and Attr entries matching the list of names in +methods+.

  def methods_matching(methods, singleton = false, &block)
    (@method_list + @attributes).each do |m|
      yield m if methods.include?(m.name) and m.singleton == singleton
    end

    each_ancestor do |parent|
      parent.methods_matching(methods, singleton, &block)
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
  # Name to use to generate the url.
  # <tt>#full_name</tt> by default.

  def name_for_path
    full_name
  end

  ##
  # Changes the visibility for new methods to +visibility+

  def ongoing_visibility=(visibility)
    @visibility = visibility
  end

  ##
  # Record +top_level+ as a file +self+ is in.

  def record_location(top_level)
    @in_files << top_level unless @in_files.include?(top_level)
  end

  ##
  # Should we remove this context from the documentation?
  #
  # The answer is yes if:
  # * #received_nodoc is +true+
  # * #any_content is +false+ (not counting includes)
  # * All #includes are modules (not a string), and their module has
  #   <tt>#remove_from_documentation? == true</tt>
  # * All classes and modules have <tt>#remove_from_documentation? == true</tt>

  def remove_from_documentation?
    @remove_from_documentation ||=
      @received_nodoc &&
      !any_content(false) &&
      @includes.all? { |i| !i.module.is_a?(String) && i.module.remove_from_documentation? } &&
      classes_and_modules.all? { |cm| cm.remove_from_documentation? }
  end

  ##
  # Removes methods and attributes with a visibility less than +min_visibility+.
  #--
  # TODO mark the visibility of attributes in the template (if not public?)

  def remove_invisible(min_visibility)
    return if min_visibility == :private
    remove_invisible_in @method_list, min_visibility
    remove_invisible_in @attributes, min_visibility
  end

  ##
  # Only called when min_visibility == :public or :private

  def remove_invisible_in(array, min_visibility) # :nodoc:
    if min_visibility == :public
      array.reject! { |e|
        e.visibility != :public and not e.force_documentation
      }
    else
      array.reject! { |e|
        e.visibility == :private and
          not e.force_documentation
      }
    end
  end

  ##
  # Tries to resolve unmatched aliases when a method
  # or attribute has just been added.

  def resolve_aliases(added)
    # resolve any pending unmatched aliases
    key = added.pretty_name
    unmatched_alias_list = @unmatched_alias_lists[key]
    return unless unmatched_alias_list
    unmatched_alias_list.each do |unmatched_alias|
      added.add_alias unmatched_alias, self
      @external_aliases.delete unmatched_alias
    end
    @unmatched_alias_lists.delete key
  end

  ##
  # Sections in this context

  def sections
    @sections.values
  end

  def sections_hash # :nodoc:
    @sections
  end

  ##
  # Creates a new section with +title+ and +comment+

  def set_current_section(title, comment)
    if @sections.key? title then
      @current_section = @sections[title]
      @current_section.comment = comment
    else
      @current_section = Section.new self, title, comment
      @sections[title] = @current_section
    end

    @current_section
  end

  ##
  # Given an array +methods+ of method names, set the visibility of each to
  # +visibility+

  def set_visibility_for(methods, visibility, singleton = false)
    methods_matching methods, singleton do |m|
      m.visibility = visibility
    end
  end

  def to_s # :nodoc:
    "#{self.class.name} #{self.full_name}"
  end

  ##
  # Return the TopLevel that owns us
  #--
  # FIXME we can be 'owned' by several TopLevel (see #record_location &
  # #in_files)

  def top_level
    return @top_level if defined? @top_level
    @top_level = self
    @top_level = @top_level.parent until RDoc::TopLevel === @top_level
    @top_level
  end

  ##
  # Upgrades NormalModule +mod+ in +enclosing+ to a +class_type+

  def upgrade_to_class mod, class_type, enclosing
    enclosing.modules_hash.delete mod.name

    klass = RDoc::ClassModule.from_module class_type, mod

    # if it was there, then we keep it even if done_documenting
    RDoc::TopLevel.classes_hash[mod.full_name] = klass
    enclosing.classes_hash[mod.name]           = klass

    klass
  end

end

