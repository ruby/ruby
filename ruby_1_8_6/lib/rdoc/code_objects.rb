# We represent the various high-level code constructs that appear
# in Ruby programs: classes, modules, methods, and so on.

require 'rdoc/tokenstream'

module RDoc


  # We contain the common stuff for contexts (which are containers)
  # and other elements (methods, attributes and so on)
  #
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

    # Default callbacks to nothing, but this is overridden for classes
    # and modules
    def remove_classes_and_modules
    end

    def remove_methods_etc
    end

    def initialize
      @document_self = true
      @document_children = true
      @force_documentation = false
      @done_documenting = false
    end

    # Access the code object's comment
    attr_reader :comment

    # Update the comment, but don't overwrite a real comment
    # with an empty one
    def comment=(comment)
      @comment = comment unless comment.empty?
    end

    # There's a wee trick we pull. Comment blocks can have directives that
    # override the stuff we extract during the parse. So, we have a special
    # class method, attr_overridable, that lets code objects list
    # those directives. Wehn a comment is assigned, we then extract
    # out any matching directives and update our object

    def CodeObject.attr_overridable(name, *aliases)
      @overridables ||= {}

      attr_accessor name

      aliases.unshift name
      aliases.each do |directive_name|
        @overridables[directive_name.to_s] = name
      end
    end

  end

  # A Context is something that can hold modules, classes, methods, 
  # attributes, aliases, requires, and includes. Classes, modules, and
  # files are all Contexts.

  class Context < CodeObject
    attr_reader   :name, :method_list, :attributes, :aliases, :constants
    attr_reader   :requires, :includes, :in_files, :visibility

    attr_reader   :sections

    class Section
      attr_reader :title, :comment, :sequence

      @@sequence = "SEC00000"

      def initialize(title, comment)
        @title = title
        @@sequence.succ!
        @sequence = @@sequence.dup
        set_comment(comment)
      end

      private

      # Set the comment for this section from the original comment block
      # If the first line contains :section:, strip it and use the rest. Otherwise
      # remove lines up to the line containing :section:, and look for 
      # those lines again at the end and remove them. This lets us write
      #
      #   # ---------------------
      #   # :SECTION: The title
      #   # The body
      #   # ---------------------

      def set_comment(comment)
        return unless comment

        if comment =~ /^.*?:section:.*$/
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
      super()

      @in_files    = []

      @name    ||= "unknown"
      @comment ||= ""
      @parent  = nil
      @visibility = :public

      @current_section = Section.new(nil, nil)
      @sections = [ @current_section ]

      initialize_methods_etc
      initialize_classes_and_modules
    end

    # map the class hash to an array externally
    def classes
      @classes.values
    end

    # map the module hash to an array externally
    def modules
      @modules.values
    end

    # Change the default visibility for new methods
    def ongoing_visibility=(vis)
      @visibility = vis
    end

    # Given an array +methods+ of method names, set the
    # visibility of the corresponding AnyMethod object

    def set_visibility_for(methods, vis, singleton=false)
      count = 0
      @method_list.each do |m|
        if methods.include?(m.name) && m.singleton == singleton
          m.visibility = vis
          count += 1
        end
      end

      return if count == methods.size || singleton

      # perhaps we need to look at attributes

      @attributes.each do |a|
        if methods.include?(a.name)
          a.visibility = vis
          count += 1
        end
      end
    end

    # Record the file that we happen to find it in
    def record_location(toplevel)
      @in_files << toplevel unless @in_files.include?(toplevel)
    end

    # Return true if at least part of this thing was defined in +file+
    def defined_in?(file)
      @in_files.include?(file)
    end

    def add_class(class_type, name, superclass)
      add_class_or_module(@classes, class_type, name, superclass)
    end

    def add_module(class_type, name)
      add_class_or_module(@modules, class_type, name, nil)
    end

    def add_method(a_method)
      puts "Adding #@visibility method #{a_method.name} to #@name" if $DEBUG
      a_method.visibility = @visibility
      add_to(@method_list, a_method)
    end

    def add_attribute(an_attribute)
      add_to(@attributes, an_attribute)
    end

    def add_alias(an_alias)
      meth = find_instance_method_named(an_alias.old_name)
      if meth
        new_meth = AnyMethod.new(an_alias.text, an_alias.new_name)
        new_meth.is_alias_for = meth
        new_meth.singleton    = meth.singleton
        new_meth.params       = meth.params
        new_meth.comment = "Alias for \##{meth.name}"
        meth.add_alias(new_meth)
        add_method(new_meth)
      else
        add_to(@aliases, an_alias)
      end
    end

    def add_include(an_include)
      add_to(@includes, an_include)
    end

    def add_constant(const)
      add_to(@constants, const)
    end

    # Requires always get added to the top-level (file) context
    def add_require(a_require)
      if self.kind_of? TopLevel
        add_to(@requires, a_require)
      else
        parent.add_require(a_require)
      end
    end

    def add_class_or_module(collection, class_type, name, superclass=nil)
      cls = collection[name]
      if cls
        puts "Reusing class/module #{name}" if $DEBUG
      else
        cls = class_type.new(name, superclass)
        puts "Adding class/module #{name} to #@name" if $DEBUG
#        collection[name] = cls if @document_self  && !@done_documenting
        collection[name] = cls if !@done_documenting
        cls.parent = self
        cls.section = @current_section
      end
      cls
    end

    def add_to(array, thing)
      array <<  thing if @document_self  && !@done_documenting
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
      return self if self.name == name
      res = @modules[name] || @classes[name]
      return res if res
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

    # Look up the given symbol. If method is non-nil, then
    # we assume the symbol references a module that
    # contains that method
    def find_symbol(symbol, method=nil)
      result = nil
      case symbol
      when /^::(.*)/
        result = toplevel.find_symbol($1)
      when /::/
        modules = symbol.split(/::/)
        unless modules.empty?
          module_name = modules.shift
          result = find_module_named(module_name)
          if result
            modules.each do |module_name|
              result = result.find_module_named(module_name)
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
      if result && method
        if !result.respond_to?(:find_local_symbol)
          p result.name
          p method
          fail
        end
        result = result.find_local_symbol(method)
      end
      result
    end
           
    def find_local_symbol(symbol)
      res = find_method_named(symbol) ||
            find_constant_named(symbol) ||
            find_attribute_named(symbol) ||
            find_module_named(symbol) 
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
    
  end


  # A TopLevel context is a source file

  class TopLevel < Context
    attr_accessor :file_stat
    attr_accessor :file_relative_name
    attr_accessor :file_absolute_name
    attr_accessor :diagram
    
    @@all_classes = {}
    @@all_modules = {}

    def TopLevel::reset
      @@all_classes = {}
      @@all_modules = {}
    end

    def initialize(file_name)
      super()
      @name = "TopLevel"
      @file_relative_name = file_name
      @file_absolute_name = file_name
      @file_stat          = File.stat(file_name)
      @diagram            = nil
    end

    def full_name
      nil
    end

    # Adding a class or module to a TopLevel is special, as we only
    # want one copy of a particular top-level class. For example,
    # if both file A and file B implement class C, we only want one
    # ClassModule object for C. This code arranges to share
    # classes and modules between files.

    def add_class_or_module(collection, class_type, name, superclass)
      cls = collection[name]
      if cls
        puts "Reusing class/module #{name}" if $DEBUG
      else
        if class_type == NormalModule
          all = @@all_modules
        else
          all = @@all_classes
        end
        cls = all[name]
        if !cls
          cls = class_type.new(name, superclass)
          all[name] = cls  unless @done_documenting
        end
        puts "Adding class/module #{name} to #@name" if $DEBUG
        collection[name] = cls unless @done_documenting
        cls.parent = self
      end
      cls
    end

    def TopLevel.all_classes_and_modules
      @@all_classes.values + @@all_modules.values
    end

    def TopLevel.find_class_named(name)
     @@all_classes.each_value do |c|
        res = c.find_class_named(name) 
        return res if res
      end
      nil
    end

    def find_local_symbol(symbol)
      find_class_or_module_named(symbol) || super
    end

    def find_class_or_module_named(symbol)
      @@all_classes.each_value {|c| return c if c.name == symbol}
      @@all_modules.each_value {|m| return m if m.name == symbol}
      nil
    end

    # Find a named module
    def find_module_named(name)
      find_class_or_module_named(name) || find_enclosing_module_named(name)
    end


  end

  # ClassModule is the base class for objects representing either a
  # class or a module.

  class ClassModule < Context

    attr_reader   :superclass
    attr_accessor :diagram

    def initialize(name, superclass = nil)
      @name       = name
      @diagram    = nil
      @superclass = superclass
      @comment    = ""
      super()
    end

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

    # Return +true+ if this object represents a module
    def is_module?
      false
    end

    # to_s is simply for debugging
    def to_s
      res = self.class.name + ": " + @name 
      res << @comment.to_s
      res << super
      res
    end

    def find_class_named(name)
      return self if full_name == name
      @classes.each_value {|c| return c if c.find_class_named(name) }
      nil
    end
  end

  # Anonymous classes
  class AnonClass < ClassModule
  end

  # Normal classes
  class NormalClass < ClassModule
  end

  # Singleton classes
  class SingleClass < ClassModule
  end

  # Module
  class NormalModule < ClassModule
    def is_module?
      true
    end
  end


  # AnyMethod is the base class for objects representing methods

  class AnyMethod < CodeObject
    attr_accessor :name
    attr_accessor :visibility
    attr_accessor :block_params
    attr_accessor :dont_rename_initialize
    attr_accessor :singleton
    attr_reader   :aliases           # list of other names for this method
    attr_accessor :is_alias_for      # or a method we're aliasing

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

    def to_s
      res = self.class.name + ": " + @name + " (" + @text + ")\n"
      res << @comment.to_s
      res
    end

    def param_seq
      p = params.gsub(/\s*\#.*/, '')
      p = p.tr("\n", " ").squeeze(" ")
      p = "(" + p + ")" unless p[0] == ?(

      if (block = block_params)
        # If this method has explicit block parameters, remove any
        # explicit &block
$stderr.puts p
        p.sub!(/,?\s*&\w+/)
$stderr.puts p

        block.gsub!(/\s*\#.*/, '')
        block = block.tr("\n", " ").squeeze(" ")
        if block[0] == ?(
          block.sub!(/^\(/, '').sub!(/\)/, '')
        end
        p << " {|#{block}| ...}"
      end
      p
    end

    def add_alias(method)
      @aliases << method
    end
  end


  # Represent an alias, which is an old_name/ new_name pair associated
  # with a particular context
  class Alias < CodeObject
    attr_accessor :text, :old_name, :new_name, :comment
    
    def initialize(text, old_name, new_name, comment)
      super()
      @text = text
      @old_name = old_name
      @new_name = new_name
      self.comment = comment
    end

    def to_s
      "alias: #{self.old_name} ->  #{self.new_name}\n#{self.comment}"
    end
  end

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

    def to_s
      "attr: #{self.name} #{self.rw}\n#{self.comment}"
    end

    def <=>(other)
      self.name <=> other.name
    end
  end

  # a required file

  class Require < CodeObject
    attr_accessor :name

    def initialize(name, comment)
      super()
      @name = name.gsub(/'|"/, "") #'
      self.comment = comment
    end

  end

  # an included module
  class Include < CodeObject
    attr_accessor :name

    def initialize(name, comment)
      super()
      @name = name
      self.comment = comment
    end

  end

end
