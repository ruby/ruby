require 'rdoc/generator'
require 'rdoc/markup/to_flow'

require 'rdoc/ri/cache'
require 'rdoc/ri/reader'
require 'rdoc/ri/writer'
require 'rdoc/ri/descriptions'

class RDoc::Generator::RI

  ##
  # Generator may need to return specific subclasses depending on the
  # options they are passed. Because of this we create them using a factory

  def self.for(options)
    new(options)
  end

  ##
  # Set up a new ri generator

  def initialize(options) #:not-new:
    @options   = options
    @ri_writer = RDoc::RI::Writer.new "."
    @markup    = RDoc::Markup.new
    @to_flow   = RDoc::Markup::ToFlow.new

    @generated = {}
  end

  ##
  # Build the initial indices and output objects based on an array of
  # TopLevel objects containing the extracted information.

  def generate(toplevels)
    RDoc::TopLevel.all_classes_and_modules.each do |cls|
      process_class cls
    end
  end

  def process_class(from_class)
    generate_class_info(from_class)

    # now recurse into this class' constituent classes
    from_class.each_classmodule do |mod|
      process_class(mod)
    end
  end

  def generate_class_info(cls)
    case cls
    when RDoc::NormalModule then
      cls_desc = RDoc::RI::ModuleDescription.new
    else
      cls_desc = RDoc::RI::ClassDescription.new
      cls_desc.superclass = cls.superclass
    end

    cls_desc.name        = cls.name
    cls_desc.full_name   = cls.full_name
    cls_desc.comment     = markup(cls.comment)

    cls_desc.attributes = cls.attributes.sort.map do |a|
      RDoc::RI::Attribute.new(a.name, a.rw, markup(a.comment))
    end

    cls_desc.constants = cls.constants.map do |c|
      RDoc::RI::Constant.new(c.name, c.value, markup(c.comment))
    end

    cls_desc.includes = cls.includes.map do |i|
      RDoc::RI::IncludedModule.new(i.name)
    end

    class_methods, instance_methods = method_list(cls)

    cls_desc.class_methods = class_methods.map do |m|
      RDoc::RI::MethodSummary.new(m.name)
    end

    cls_desc.instance_methods = instance_methods.map do |m|
      RDoc::RI::MethodSummary.new(m.name)
    end

    update_or_replace(cls_desc)

    class_methods.each do |m|
      generate_method_info(cls_desc, m)
    end

    instance_methods.each do |m|
      generate_method_info(cls_desc, m)
    end
  end

  def generate_method_info(cls_desc, method)
    meth_desc = RDoc::RI::MethodDescription.new
    meth_desc.name = method.name
    meth_desc.full_name = cls_desc.full_name
    if method.singleton
      meth_desc.full_name += "::"
    else
      meth_desc.full_name += "#"
    end
    meth_desc.full_name << method.name

    meth_desc.comment = markup(method.comment)
    meth_desc.params = params_of(method)
    meth_desc.visibility = method.visibility.to_s
    meth_desc.is_singleton = method.singleton
    meth_desc.block_params = method.block_params

    meth_desc.aliases = method.aliases.map do |a|
      RDoc::RI::AliasName.new(a.name)
    end

    @ri_writer.add_method(cls_desc, meth_desc)
  end

  private

  ##
  # Returns a list of class and instance methods that we'll be documenting

  def method_list(cls)
    list = cls.method_list
    unless @options.show_all
      list = list.find_all do |m|
        m.visibility == :public || m.visibility == :protected || m.force_documentation
      end
    end

    c = []
    i = []
    list.sort.each do |m|
      if m.singleton
        c << m
      else
        i << m
      end
    end
    return c,i
  end

  def params_of(method)
    if method.call_seq
      method.call_seq
    else
      params = method.params || ""

      p = params.gsub(/\s*\#.*/, '')
      p = p.tr("\n", " ").squeeze(" ")
      p = "(" + p + ")" unless p[0] == ?(

      if (block = method.block_params)
        block.gsub!(/\s*\#.*/, '')
        block = block.tr("\n", " ").squeeze(" ")
        if block[0] == ?(
          block.sub!(/^\(/, '').sub!(/\)/, '')
        end
        p << " {|#{block.strip}| ...}"
      end
      p
    end
  end

  def markup(comment)
    return nil if !comment || comment.empty?

    # Convert leading comment markers to spaces, but only
    # if all non-blank lines have them

    if comment =~ /^(?>\s*)[^\#]/
      content = comment
    else
      content = comment.gsub(/^\s*(#+)/)  { $1.tr('#',' ') }
    end
    @markup.convert(content, @to_flow)
  end

  ##
  # By default we replace existing classes with the same name. If the
  # --merge option was given, we instead merge this definition into an
  # existing class. We add our methods, aliases, etc to that class, but do
  # not change the class's description.

  def update_or_replace(cls_desc)
    old_cls = nil

    if @options.merge
      rdr = RDoc::RI::Reader.new RDoc::RI::Cache.new(@options.op_dir)

      namespace = rdr.top_level_namespace
      namespace = rdr.lookup_namespace_in(cls_desc.name, namespace)
      if namespace.empty?
        $stderr.puts "You asked me to merge this source into existing "
        $stderr.puts "documentation. This file references a class or "
        $stderr.puts "module called #{cls_desc.name} which I don't"
        $stderr.puts "have existing documentation for."
        $stderr.puts
        $stderr.puts "Perhaps you need to generate its documentation first"
        exit 1
      else
        old_cls = namespace[0]
      end
    end

    prev_cls = @generated[cls_desc.full_name]

    if old_cls and not prev_cls then
      old_desc = rdr.get_class old_cls
      cls_desc.merge_in old_desc
    end

    if prev_cls then
      cls_desc.merge_in prev_cls
    end

    @generated[cls_desc.full_name] = cls_desc

    @ri_writer.remove_class cls_desc
    @ri_writer.add_class cls_desc
  end

end

