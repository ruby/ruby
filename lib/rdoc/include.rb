require 'rdoc/code_object'

##
# A Module include in a class with \#include

class RDoc::Include < RDoc::CodeObject

  ##
  # Name of included module

  attr_accessor :name

  ##
  # Creates a new Include for +name+ with +comment+

  def initialize(name, comment)
    super()
    @name = name
    self.comment = comment
  end

  ##
  # Includes are sorted by name

  def <=> other
    return unless self.class === other

    name <=> other.name
  end

  def == other # :nodoc:
    self.class == other.class and
      self.name == other.name
  end

  ##
  # Full name based on #module

  def full_name
    m = self.module
    RDoc::ClassModule === m ? m.full_name : @name
  end

  def inspect # :nodoc:
    "#<%s:0x%x %s.include %s>" % [
      self.class,
      object_id,
      parent_name, @name,
    ]
  end

  ##
  # Attempts to locate the included module object.  Returns the name if not
  # known.

  def module
    RDoc::TopLevel.find_module_named(@name) || @name
  end

end

