require 'yaml'

# Descriptions are created by RDoc (in ri_generator) and
# written out in serialized form into the documentation
# tree. ri then reads these to generate the documentation

module RI
  Alias          = Struct.new(:old_name, :new_name)
  AliasName      = Struct.new(:name)
  Attribute      = Struct.new(:name, :rw, :comment)
  Constant       = Struct.new(:name, :value, :comment)
  IncludedModule = Struct.new(:name)
  
  class MethodSummary
    attr_accessor :name
    def initialize(name="")
      @name = name
    end

    def <=>(other)
      self.name <=> other.name
    end
  end


  class Description
    attr_accessor :name
    attr_accessor :full_name
    attr_accessor :comment
    
    def serialize
      self.to_yaml
    end

    def Description.deserialize(from)
      YAML.load(from)
    end
  end
  
  class ClassDescription < Description
    
    attr_accessor :class_methods
    attr_accessor :instance_methods
    attr_accessor :attributes
    attr_accessor :constants
    attr_accessor :superclass
    attr_accessor :includes

    # merge in another class desscription into this one
    def merge_in(old)
      @class_methods.concat(old.class_methods).sort!
      @instance_methods.concat(old.instance_methods).sort!
      @attributes.concat(old.attributes).sort!
      @constants.concat(old.constants).sort!
      @includes.concat(old.includes).sort!
    end
  end
  
  class MethodDescription < Description
    
    attr_accessor :is_class_method
    attr_accessor :visibility
    attr_accessor :block_params
    attr_accessor :is_singleton
    attr_accessor :aliases
    attr_accessor :is_alias_for
    attr_accessor :params

  end
  
end
