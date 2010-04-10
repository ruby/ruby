require 'rdoc/context'

##
# ClassModule is the base class for objects representing either a class or a
# module.

class RDoc::ClassModule < RDoc::Context

  MARSHAL_VERSION = 0 # :nodoc:

  attr_accessor :diagram

  ##
  # Creates a new ClassModule with +name+ with optional +superclass+

  def initialize(name, superclass = 'Object')
    @diagram    = nil
    @full_name  = nil
    @name       = name
    @superclass = superclass
    super()
  end

  ##
  # Ancestors list for this ClassModule (abstract)

  def ancestors
    raise NotImplementedError
  end

  ##
  # Appends +comment+ to the current comment, but separated by a rule.  Works
  # more like <tt>+=</tt>.

  def comment=(comment)
    return if comment.empty?

    comment = "#{@comment}\n---\n#{normalize_comment comment}" unless
      @comment.empty?

    super
  end

  ##
  # Finds a class or module with +name+ in this namespace or its descendents

  def find_class_named(name)
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

  ##
  # 'module' or 'class'

  def type
    module? ? 'module' : 'class'
  end

  def marshal_dump # :nodoc:
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
    initialize_methods_etc
    @document_self    = true
    @done_documenting = false
    @current_section  = nil

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
  # Path to this class or module

  def path
    http_url RDoc::RDoc.current.generator.class_dir
  end

  ##
  # Get the superclass of this class.  Attempts to retrieve the superclass
  # object, returns the name if it is not known.

  def superclass
    RDoc::TopLevel.find_class_named_from(@superclass, parent) || @superclass
  end

  ##
  # Set the superclass of this class to +superclass+

  def superclass=(superclass)
    raise NoMethodError, "#{full_name} is a module" if module?

    @superclass = superclass if @superclass.nil? or @superclass == 'Object'
  end

  def to_s # :nodoc:
    "#{self.class}: #{full_name} #{@comment} #{super}"
  end

end

