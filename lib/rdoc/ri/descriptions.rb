require 'yaml'
require 'rdoc/markup/fragments'
require 'rdoc/ri'

##
# Descriptions are created by RDoc (in ri_generator) and written out in
# serialized form into the documentation tree. ri then reads these to generate
# the documentation

class RDoc::RI::NamedThing
  attr_reader :name
  def initialize(name)
    @name = name
  end

  def <=>(other)
    @name <=> other.name
  end

  def hash
    @name.hash
  end

  def eql?(other)
    @name.eql?(other)
  end
end

class RDoc::RI::AliasName < RDoc::RI::NamedThing; end

class RDoc::RI::Attribute < RDoc::RI::NamedThing
  attr_reader :rw, :comment

  def initialize(name, rw, comment)
    super(name)
    @rw = rw
    @comment = comment
  end
end

class RDoc::RI::Constant < RDoc::RI::NamedThing
  attr_reader :value, :comment

  def initialize(name, value, comment)
    super(name)
    @value = value
    @comment = comment
  end
end

class RDoc::RI::IncludedModule < RDoc::RI::NamedThing; end

class RDoc::RI::MethodSummary < RDoc::RI::NamedThing
  def initialize(name="")
    super
  end
end

class RDoc::RI::Description
  attr_accessor :name
  attr_accessor :full_name
  attr_accessor :comment

  def serialize
    self.to_yaml
  end

  def self.deserialize(from)
    YAML.load(from)
  end

  def <=>(other)
    @name <=> other.name
  end
end

class RDoc::RI::ModuleDescription < RDoc::RI::Description

  attr_accessor :class_methods
  attr_accessor :class_method_extensions
  attr_accessor :instance_methods
  attr_accessor :instance_method_extensions
  attr_accessor :attributes
  attr_accessor :constants
  attr_accessor :includes

  # merge in another class description into this one
  def merge_in(old)
    merge(@class_methods, old.class_methods)
    merge(@instance_methods, old.instance_methods)
    merge(@attributes, old.attributes)
    merge(@constants, old.constants)
    merge(@includes, old.includes)
    if @comment.nil? || @comment.empty?
      @comment = old.comment
    else
      unless old.comment.nil? or old.comment.empty? then
        if @comment.nil? or @comment.empty? then
          @comment = old.comment
        else
          @comment << RDoc::Markup::Flow::RULE.new
          @comment.concat old.comment
        end
      end
    end
  end

  def display_name
      "Module"
  end

  # the 'ClassDescription' subclass overrides this
  # to format up the name of a parent
  def superclass_string
    nil
  end

  private

  def merge(into, from)
    names = {}
    into.each {|i| names[i.name] = i }
    from.each {|i| names[i.name] = i }
    into.replace(names.keys.sort.map {|n| names[n]})
  end
end

class RDoc::RI::ClassDescription < RDoc::RI::ModuleDescription
  attr_accessor :superclass

  def display_name
      "Class"
  end

  def superclass_string
    if @superclass && @superclass != "Object"
      @superclass
    else
      nil
    end
  end
end

class RDoc::RI::MethodDescription < RDoc::RI::Description

  attr_accessor :is_class_method
  attr_accessor :visibility
  attr_accessor :block_params
  attr_accessor :is_singleton
  attr_accessor :aliases
  attr_accessor :is_alias_for
  attr_accessor :params
  attr_accessor :source_path

end

