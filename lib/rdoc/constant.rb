require 'rdoc/code_object'

##
# A constant

class RDoc::Constant < RDoc::CodeObject

  ##
  # The constant's name

  attr_accessor :name

  ##
  # The constant's value

  attr_accessor :value

  ##
  # Creates a new constant with +name+, +value+ and +comment+

  def initialize(name, value, comment)
    super()
    @name = name
    @value = value
    self.comment = comment
  end

  ##
  # Constants are ordered by name

  def <=> other
    return unless self.class === other

    [parent_name, name] <=> [other.parent_name, other.name]
  end

  def == other
    self.class == other.class and
      @parent == other.parent and
      @name == other.name
  end

  def inspect # :nodoc:
      "#<%s:0x%x %s::%s>" % [
        self.class, object_id,
        parent_name, @name,
      ]
  end

  ##
  # Path to this constant

  def path
    "#{@parent.path}##{@name}"
  end

end

