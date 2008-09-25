# We represent the various high-level code constructs that appear
# in Ruby programs: classes, modules, methods, and so on.

require 'rdoc/tokenstream'

module RDoc

  ##
  # We contain the common stuff for contexts (which are containers) and other
  # elements (methods, attributes and so on)

  class CodeObject

    attr_accessor :parent

    # We are the model of the code, but we know that at some point
    # we will be worked on by viewers. By implementing the Viewable
    # protocol, viewers can associated themselves with these objects.

    attr_accessor :viewer

    # are we done documenting (ie, did we come across a :enddoc:)?

    attr_accessor :done_documenting

    # Which section are we in

    attr_accessor :section

    # do we document ourselves?

    attr_reader :document_self

    def initialize
      @document_self = true
      @document_children = true
      @force_documentation = false
      @done_documenting = false
    end

    def document_self=(val)
      @document_self = val
      if !val
	remove_methods_etc
      end
    end

    # set and cleared by :startdoc: and :enddoc:, this is used to toggle
    # the capturing of documentation
    def start_doc
      @document_self = true
      @document_children = true
    end

    def stop_doc
      @document_self = false
      @document_children = false
    end

    # do we document ourselves and our children

    attr_reader :document_children

    def document_children=(val)
      @document_children = val
      if !val
	remove_classes_and_modules
      end
    end

    # Do we _force_ documentation, even is we wouldn't normally show the entity
    attr_accessor :force_documentation

    def parent_file_name
      @parent ? @parent.file_base_name : '(unknown)'
    end

    def parent_name
      @parent ? @parent.name : '(unknown)'
    end

    # Default callbacks to nothing, but this is overridden for classes
    # and modules
    def remove_classes_and_modules
    end

    def remove_methods_etc
    end

    # Access the code object's comment
    attr_reader :comment

    # Update the comment, but don't overwrite a real comment with an empty one
    def comment=(comment)
      @comment = comment unless comment.empty?
    end

    # There's a wee trick we pull. Comment blocks can have directives that
    # override the stuff we extract during the parse. So, we have a special
    # class method, attr_overridable, that lets code objects list
    # those directives. Wehn a comment is assigned, we then extract
    # out any matching directives and update our object

    def self.attr_overridable(name, *aliases)
      @overridables ||= {}

      attr_accessor name

      aliases.unshift name
      aliases.each do |directive_name|
        @overridables[directive_name.to_s] = name
      end
    end

  end

  ##
  # A Context is something that can hold modules, classes, methods,
  # attributes, aliases, requires, and includes. Classes, modules, and files
  # are all Contexts.

  class Context < CodeObject

    attr_reader :aliases
    attr_reader :attributes
    attr_reader :constants
    attr_reader :current_section
    attr_reader :in_files
    attr_reader :includes
    attr_reader :method_list
    attr_reader :name
    attr_reader :requires
    attr_reader :sections
    attr_reader :visibility

    class Section
      attr_reader :title, :comment, :sequence

      @@sequence = "SEC00000"

      def initialize(title, comment)
        @title = title
        @@sequence.succ!
        @sequence = @@sequence.dup
        @comment = nil
        set_comment(comment)
      end

      def ==(other)
        self.class === other and @sequence == other.sequence
      end

      def inspect
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
      #   # ---------------------
      #   # :SECTION: The title
      #   # The body
      #   # ---------------------

      def set_comment(comment)
        return unless comment

        if comment =~ /^#[ \t]*:section:.*\n/
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

    def initialize
      super

      @in_files = []

      @name    ||= "unknown"
      @comment ||= ""
      @parent  = nil
      @visibility = :public

      @current_section = Section.new(nil, nil)
      @sections = [ @current_section ]

      initialize_methods_etc
      initialize_classes_and_modules
    end

    ##
    # map the class hash to an array externally

    def classes
      @classes.values
    end

    ##
    # map the module hash to an array externally

    def modules
      @modules.values
    end

    ##
    # return the classes Hash (only to be used internally)

    def classes_hash
      @classes
    end
    protected :classes_hash

    ##
    # return the modules Hash (only to be used internally)

    def modules_hash
      @modules
    end
    protected :modules_hash

    ##
    # Change the default visibility for new methods

    def ongoing_visibility=(vis)
      @visibility = vis
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

      # perhaps we need to look at attributes

      @attributes.each do |a|
        yield a if methods.include? a.name
      end
    end

    ##
    # Given an array +methods+ of method names, set the visibility of the
    # corresponding AnyMethod object

    def set_visibility_for(methods, vis, singleton = false)
      methods_matching methods, singleton do |m|
        m.visibility = vis
      end
    end

    ##
    # Record the file that we happen to find it in

    def record_location(toplevel)
      @in_files << toplevel unless @in_files.include?(toplevel)
    end

    # Return true if at least part of this thing was defined in +file+
    def defined_in?(file)
      @in_files.include?(file)
    end

    def add_class(class_type, name, superclass)
      klass = add_class_or_module @classes, class_type, name, superclass

      #
      # If the parser encounters Container::Item before encountering
      # Container, then it assumes that Container is a module.  This
      # may not be the case, so remove Container from the module list
      # if present and transfer any contained classes and modules to
      # the new class.
      #
      mod = @modules.delete(name)

      if mod then
        klass.classes_hash.update(mod.classes_hash)
        klass.modules_hash.update(mod.modules_hash)
        klass.method_list.concat(mod.method_list)
      end

      return klass
    end

    def add_module(class_type, name)
      add_class_or_module(@modules, class_type, name, nil)
    end

    def add_method(a_method)
      a_method.visibility = @visibility
      add_to(@method_list, a_method)

      unmatched_alias_list = @unmatched_alias_lists[a_method.name]
      if unmatched_alias_list then
        unmatched_alias_list.each do |unmatched_alias|
          add_alias_impl unmatched_alias, a_method
          @aliases.delete unmatched_alias
        end

        @unmatched_alias_lists.delete a_method.name
      end
    end

    def add_attribute(an_attribute)
      add_to(@attributes, an_attribute)
    end

    def add_alias_impl(an_alias, meth)
      new_meth = AnyMethod.new(an_alias.text, an_alias.new_name)
      new_meth.is_alias_for = meth
      new_meth.singleton    = meth.singleton
      new_meth.params       = meth.params
      new_meth.comment = "Alias for \##{meth.name}"
      meth.add_alias(new_meth)
      add_method(new_meth)
    end
    
    def add_alias(an_alias)
      meth = find_instance_method_named(an_alias.old_name)

      if meth then
        add_alias_impl(an_alias, meth)
      else
        add_to(@aliases, an_alias)
        unmatched_alias_list = @unmatched_alias_lists[an_alias.old_name] ||= []
        unmatched_alias_list.push(an_alias)
      end

      an_alias
    end

    def add_include(an_include)
      add_to(@includes, an_include)
    end

    def add_constant(const)
      add_to(@constants, const)
    end

    # Requires always get added to the top-level (file) context
    def add_require(a_require)
      if TopLevel === self then
        add_to @requires, a_require
      else
        parent.add_require a_require
      end
    end

    def add_class_or_module(collection, class_type, name, superclass=nil)
      cls = collection[name]

      if cls then
        cls.superclass = superclass unless cls.module?
        puts "Reusing class/module #{name}" if $DEBUG_RDOC
      else
        cls = class_type.new(name, superclass)
#        collection[name] = cls if @document_self  && !@done_documenting
        collection[name] = cls if !@done_documenting
        cls.parent = self
        cls.section = @current_section
      end
      cls
    end

    def add_to(array, thing)
      array << thing if @document_self and not @done_documenting
      thing.parent = self
      thing.section = @current_section
    end

    # If a class's documentation is turned off after we've started
    # collecting methods etc., we need to remove the ones
    # we have

    def remove_methods_etc
      initialize_methods_etc
    end

    def initialize_methods_etc
      @method_list = []
      @attributes  = []
      @aliases     = []
      @requires    = []
      @includes    = []
      @constants   = []

      # This Hash maps a method name to a list of unmatched
      # aliases (aliases of a method not yet encountered).
      @unmatched_alias_lists = {}
    end

    # and remove classes and modules when we see a :nodoc: all
    def remove_classes_and_modules
      initialize_classes_and_modules
    end

    def initialize_classes_and_modules
      @classes     = {}
      @modules     = {}
    end

    # Find a named module
    def find_module_named(name)
      # First check the enclosed modules, then check the module itself,
      # then check the enclosing modules (this mirrors the check done by
      # the Ruby parser)
      res = @modules[name] || @classes[name]
      return res if res
      return self if self.name == name
      find_enclosing_module_named(name)
    end

    # find a module at a higher scope
    def find_enclosing_module_named(name)
      parent && parent.find_module_named(name)
    end

    # Iterate over all the classes and modules in
    # this object

    def each_classmodule
      @modules.each_value {|m| yield m}
      @classes.each_value {|c| yield c}
    end

    def each_method
      @method_list.each {|m| yield m}
    end

    def each_attribute 
      @attributes.each {|a| yield a}
    end

    def each_constant
      @constants.each {|c| yield c}
    end

    # Return the toplevel that owns us

    def toplevel
      return @toplevel if defined? @toplevel
      @toplevel = self
      @toplevel = @toplevel.parent until TopLevel === @toplevel
      @toplevel
    end

    # allow us to sort modules by name
    def <=>(other)
      name <=> other.name
    end

    ##
    # Look up +symbol+.  If +method+ is non-nil, then we assume the symbol
    # references a module that contains that method.

    def find_symbol(symbol, method = nil)
      result = nil

      case symbol
      when /^::(.*)/ then
        result = toplevel.find_symbol($1)
      when /::/ then
        modules = symbol.split(/::/)

        unless modules.empty? then
          module_name = modules.shift
          result = find_module_named(module_name)

          if result then
            modules.each do |name|
              result = result.find_module_named(name)
              break unless result
            end
          end
        end

      else
        # if a method is specified, then we're definitely looking for
        # a module, otherwise it could be any symbol
        if method
          result = find_module_named(symbol)
        else
          result = find_local_symbol(symbol)
          if result.nil?
            if symbol =~ /^[A-Z]/
              result = parent
              while result && result.name != symbol
                result = result.parent
              end
            end
          end
        end
      end

      if result and method then
        fail unless result.respond_to? :find_local_symbol
        result = result.find_local_symbol(method)
      end

      result
    end

    def find_local_symbol(symbol)
      res = find_method_named(symbol) ||
            find_constant_named(symbol) ||
            find_attribute_named(symbol) ||
            find_module_named(symbol) ||
            find_file_named(symbol)
    end

    # Handle sections

    def set_current_section(title, comment)
      @current_section = Section.new(title, comment)
      @sections << @current_section
    end

    private

    # Find a named method, or return nil
    def find_method_named(name)
      @method_list.find {|meth| meth.name == name}
    end

    # Find a named instance method, or return nil
    def find_instance_method_named(name)
      @method_list.find {|meth| meth.name == name && !meth.singleton}
    end

    # Find a named constant, or return nil
    def find_constant_named(name)
      @constants.find {|m| m.name == name}
    end

    # Find a named attribute, or return nil
    def find_attribute_named(name)
      @attributes.find {|m| m.name == name}
    end

    ##
    # Find a named file, or return nil

    def find_file_named(name)
      toplevel.class.find_file_named(name)
    end

  end

  ##
  # A TopLevel context is a source file

  class TopLevel < Context
    attr_accessor :file_stat
    attr_accessor :file_relative_name
    attr_accessor :file_absolute_name
    attr_accessor :diagram

    @@all_classes = {}
    @@all_modules = {}
    @@all_files   = {}

    def self.reset
      @@all_classes = {}
      @@all_modules = {}
      @@all_files   = {}
    end

    def initialize(file_name)
      super()
      @name = "TopLevel"
      @file_relative_name    = file_name
      @file_absolute_name    = file_name
      @file_stat             = File.stat(file_name)
      @diagram               = nil
      @@all_files[file_name] = self
    end

    def file_base_name
      File.basename @file_absolute_name
    end

    def full_name
      nil
    end

    ##
    # Adding a class or module to a TopLevel is special, as we only want one
    # copy of a particular top-level class. For example, if both file A and
    # file B implement class C, we only want one ClassModule object for C.
    # This code arranges to share classes and modules between files.

    def add_class_or_module(collection, class_type, name, superclass)
      cls = collection[name]

      if cls then
        cls.superclass = superclass unless cls.module?
        puts "Reusing class/module #{cls.full_name}" if $DEBUG_RDOC
      else
        if class_type == NormalModule then
          all = @@all_modules
        else
          all = @@all_classes
        end

        cls = all[name]

        if !cls then
          cls = class_type.new name, superclass
          all[name] = cls unless @done_documenting
        else
          # If the class has been encountered already, check that its
          # superclass has been set (it may not have been, depending on
          # the context in which it was encountered).
          if class_type == NormalClass
            if !cls.superclass then
              cls.superclass = superclass
            end
          end
        end

        collection[name] = cls unless @done_documenting

        cls.parent = self
      end

      cls
    end

    def self.all_classes_and_modules
      @@all_classes.values + @@all_modules.values
    end

    def self.find_class_named(name)
     @@all_classes.each_value do |c|
        res = c.find_class_named(name) 
        return res if res
      end
      nil
    end

    def self.find_file_named(name)
      @@all_files[name]
    end

    def find_local_symbol(symbol)
      find_class_or_module_named(symbol) || super
    end

    def find_class_or_module_named(symbol)
      @@all_classes.each_value {|c| return c if c.name == symbol}
      @@all_modules.each_value {|m| return m if m.name == symbol}
      nil
    end

    ##
    # Find a named module

    def find_module_named(name)
      find_class_or_module_named(name) || find_enclosing_module_named(name)
    end

    def inspect
      "#<%s:0x%x %p modules: %p classes: %p>" % [
        self.class, object_id,
        file_base_name,
        @modules.map { |n,m| m },
        @classes.map { |n,c| c }
      ]
    end

  end

  ##
  # ClassModule is the base class for objects representing either a class or a
  # module.

  class ClassModule < Context

    attr_accessor :diagram

    def initialize(name, superclass = nil)
      @name       = name
      @diagram    = nil
      @superclass = superclass
      @comment    = ""
      super()
    end

    def find_class_named(name)
      return self if full_name == name
      @classes.each_value {|c| return c if c.find_class_named(name) }
      nil
    end

    ##
    # Return the fully qualified name of this class or module

    def full_name
      if @parent && @parent.full_name
        @parent.full_name + "::" + @name
      else
        @name
      end
    end

    def http_url(prefix)
      path = full_name.split("::")
      File.join(prefix, *path) + ".html"
    end

    ##
    # Does this object represent a module?

    def module?
      false
    end

    ##
    # Get the superclass of this class.  Attempts to retrieve the superclass'
    # real name by following module nesting.

    def superclass
      raise NoMethodError, "#{full_name} is a module" if module?

      scope = self

      begin
        superclass = scope.classes.find { |c| c.name == @superclass }

        return superclass.full_name if superclass
        scope = scope.parent
      end until scope.nil? or TopLevel === scope

      @superclass
    end

    ##
    # Set the superclass of this class

    def superclass=(superclass)
      raise NoMethodError, "#{full_name} is a module" if module?

      if @superclass.nil? or @superclass == 'Object' then
        @superclass = superclass 
      end
    end

    def to_s
      "#{self.class}: #{@name} #{@comment} #{super}"
    end

  end

  ##
  # Anonymous classes

  class AnonClass < ClassModule
  end

  ##
  # Normal classes

  class NormalClass < ClassModule

    def inspect
      superclass = @superclass ? " < #{@superclass}" : nil
      "<%s:0x%x class %s%s includes: %p attributes: %p methods: %p aliases: %p>" % [
        self.class, object_id,
        @name, superclass, @includes, @attributes, @method_list, @aliases
      ]
    end

  end

  ##
  # Singleton classes

  class SingleClass < ClassModule
  end

  ##
  # Module

  class NormalModule < ClassModule

    def comment=(comment)
      return if comment.empty?
      comment = @comment << "# ---\n" << comment unless @comment.empty?

      super
    end

    def inspect
      "#<%s:0x%x module %s includes: %p attributes: %p methods: %p aliases: %p>" % [
        self.class, object_id,
        @name, @includes, @attributes, @method_list, @aliases
      ]
    end

    def module?
      true
    end

  end

  ##
  # AnyMethod is the base class for objects representing methods

  class AnyMethod < CodeObject

    attr_accessor :name
    attr_accessor :visibility
    attr_accessor :block_params
    attr_accessor :dont_rename_initialize
    attr_accessor :singleton
    attr_reader :text

    # list of other names for this method
    attr_reader   :aliases

    # method we're aliasing
    attr_accessor :is_alias_for

    attr_overridable :params, :param, :parameters, :parameter

    attr_accessor :call_seq

    include TokenStream

    def initialize(text, name)
      super()
      @text = text
      @name = name
      @token_stream  = nil
      @visibility    = :public
      @dont_rename_initialize = false
      @block_params  = nil
      @aliases       = []
      @is_alias_for  = nil
      @comment = ""
      @call_seq = nil
    end

    def <=>(other)
      @name <=> other.name
    end

    def add_alias(method)
      @aliases << method
    end

    def inspect
      alias_for = @is_alias_for ? " (alias for #{@is_alias_for.name})" : nil
      "#<%s:0x%x %s%s%s (%s)%s>" % [
        self.class, object_id,
        parent_name,
        singleton ? '::' : '#',
        name,
        visibility,
        alias_for,
      ]
    end

    def param_seq
      params = params.gsub(/\s*\#.*/, '')
      params = params.tr("\n", " ").squeeze(" ")
      params = "(#{params})" unless p[0] == ?(

      if block = block_params then # yes, =
        # If this method has explicit block parameters, remove any explicit
        # &block
        params.sub!(/,?\s*&\w+/)

        block.gsub!(/\s*\#.*/, '')
        block = block.tr("\n", " ").squeeze(" ")
        if block[0] == ?(
          block.sub!(/^\(/, '').sub!(/\)/, '')
        end
        params << " { |#{block}| ... }"
      end

      params
    end

    def to_s
      res = self.class.name + ": " + @name + " (" + @text + ")\n"
      res << @comment.to_s
      res
    end

  end

  ##
  # GhostMethod represents a method referenced only by a comment

  class GhostMethod < AnyMethod
  end

  ##
  # MetaMethod represents a meta-programmed method

  class MetaMethod < AnyMethod
  end

  ##
  # Represent an alias, which is an old_name/ new_name pair associated with a
  # particular context

  class Alias < CodeObject

    attr_accessor :text, :old_name, :new_name, :comment

    def initialize(text, old_name, new_name, comment)
      super()
      @text = text
      @old_name = old_name
      @new_name = new_name
      self.comment = comment
    end

    def inspect
      "#<%s:0x%x %s.alias_method %s, %s>" % [
        self.class, object_id,
        parent.name, @old_name, @new_name,
      ]
    end

    def to_s
      "alias: #{self.old_name} ->  #{self.new_name}\n#{self.comment}"
    end

  end

  ##
  # Represent a constant

  class Constant < CodeObject
    attr_accessor :name, :value

    def initialize(name, value, comment)
      super()
      @name = name
      @value = value
      self.comment = comment
    end
  end

  ##
  # Represent attributes

  class Attr < CodeObject
    attr_accessor :text, :name, :rw, :visibility

    def initialize(text, name, rw, comment)
      super()
      @text = text
      @name = name
      @rw = rw
      @visibility = :public
      self.comment = comment
    end

    def <=>(other)
      self.name <=> other.name
    end

    def inspect
      attr = case rw
             when 'RW' then :attr_accessor
             when 'R'  then :attr_reader
             when 'W'  then :attr_writer
             else
               " (#{rw})"
             end

      "#<%s:0x%x %s.%s :%s>" % [
        self.class, object_id,
        parent_name, attr, @name,
      ]
    end

    def to_s
      "attr: #{self.name} #{self.rw}\n#{self.comment}"
    end

  end

  ##
  # A required file

  class Require < CodeObject
    attr_accessor :name

    def initialize(name, comment)
      super()
      @name = name.gsub(/'|"/, "") #'
      self.comment = comment
    end

    def inspect
      "#<%s:0x%x require '%s' in %s>" % [
        self.class,
        object_id,
        @name,
        parent_file_name,
      ]
    end

  end

  ##
  # An included module

  class Include < CodeObject

    attr_accessor :name

    def initialize(name, comment)
      super()
      @name = name
      self.comment = comment

    end

    def inspect
      "#<%s:0x%x %s.include %s>" % [
        self.class,
        object_id,
        parent_name, @name,
      ]
    end

  end

end
