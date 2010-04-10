require 'rdoc/code_object'

##
# An attribute created by \#attr, \#attr_reader, \#attr_writer or
# \#attr_accessor

class RDoc::Attr < RDoc::CodeObject

  MARSHAL_VERSION = 0 # :nodoc:

  ##
  # Name of the attribute

  attr_accessor :name

  ##
  # Is the attribute readable, writable or both?

  attr_accessor :rw

  ##
  # Source file token stream

  attr_accessor :text

  ##
  # public, protected, private

  attr_accessor :visibility

  def initialize(text, name, rw, comment)
    super()
    @text = text
    @name = name
    @rw = rw
    @visibility = :public
    self.comment = comment
  end

  ##
  # Attributes are ordered by name

  def <=>(other)
    self.name <=> other.name
  end

  ##
  # Attributes are equal when their names and rw is identical

  def == other
    self.class == other.class and
      self.name == other.name and
      self.rw == other.rw
  end

  ##
  # Returns nil, for duck typing with RDoc::AnyMethod

  def arglists
  end

  ##
  # Returns nil, for duck typing with RDoc::AnyMethod

  def block_params
  end

  ##
  # Returns nil, for duck typing with RDoc::AnyMethod

  def call_seq
  end

  ##
  # Partially bogus as Attr has no parent.  For duck typing with
  # RDoc::AnyMethod.

  def full_name
    @full_name ||= "#{@parent ? @parent.full_name : '(unknown)'}##{name}"
  end

  ##
  # An HTML id-friendly representation of #name

  def html_name
    @name.gsub(/[^a-z]+/, '-')
  end

  def inspect # :nodoc:
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

  ##
  # Dumps this Attr for use by ri.  See also #marshal_load

  def marshal_dump
    [ MARSHAL_VERSION,
      @name,
      full_name,
      @rw,
      @visibility,
      parse(@comment),
    ]
  end

  ##
  # Loads this AnyMethod from +array+.  For a loaded AnyMethod the following
  # methods will return cached values:
  #
  # * #full_name
  # * #parent_name

  def marshal_load array
    @name       = array[1]
    @full_name  = array[2]
    @rw         = array[3]
    @visibility = array[4]
    @comment    = array[5]

    @parent_name = @full_name
  end

  ##
  # Name of our parent with special handling for un-marshaled methods

  def parent_name
    @parent_name || super
  end

  ##
  # For duck typing with RDoc::AnyMethod, returns nil

  def params
    nil
  end

  ##
  # URL path for this attribute

  def path
    "#{@parent.path}##{@name}"
  end

  ##
  # For duck typing with RDoc::AnyMethod

  def singleton
    false
  end

  def to_s # :nodoc:
    "#{type} #{name}\n#{comment}"
  end

  ##
  # Returns attr_reader, attr_writer or attr_accessor as appropriate

  def type
    case @rw
    when 'RW' then 'attr_accessor'
    when 'R'  then 'attr_reader'
    when 'W'  then 'attr_writer'
    end
  end

end

