# We're responsible for generating all the HTML files
# from the object tree defined in code_objects.rb. We
# generate:
#
# [files]   an html file for each input file given. These
#           input files appear as objects of class
#           TopLevel
#
# [classes] an html file for each class or module encountered.
#           These classes are not grouped by file: if a file
#           contains four classes, we'll generate an html
#           file for the file itself, and four html files 
#           for the individual classes. 
#
# [indices] we generate three indices for files, classes,
#           and methods. These are displayed in a browser
#           like window with three index panes across the
#           top and the selected description below
#
# Method descriptions appear in whatever entity (file, class,
# or module) that contains them.
#
# We generate files in a structure below a specified subdirectory,
# normally +doc+.
#
#  opdir
#     |
#     |___ files
#     |       |__  per file summaries
#     |
#     |___ classes
#             |__ per class/module descriptions
#
# HTML is generated using the Template class.
#

require 'ftools'

require 'rdoc/options'
require 'rdoc/template'
require 'rdoc/markup/simple_markup'
require 'rdoc/markup/simple_markup/to_flow'
require 'cgi'

require 'rdoc/ri/ri_cache'
require 'rdoc/ri/ri_reader'
require 'rdoc/ri/ri_writer'
require 'rdoc/ri/ri_descriptions'

module Generators


  class RIGenerator

    # Generators may need to return specific subclasses depending
    # on the options they are passed. Because of this
    # we create them using a factory

    def RIGenerator.for(options)
      new(options)
    end

    class <<self
      protected :new
    end

    # Set up a new HTML generator. Basically all we do here is load
    # up the correct output temlate

    def initialize(options) #:not-new:
      @options   = options
      @ri_writer = RI::RiWriter.new(options.op_dir)
      @markup    = SM::SimpleMarkup.new
      @to_flow   = SM::ToFlow.new
    end


    ##
    # Build the initial indices and output objects
    # based on an array of TopLevel objects containing
    # the extracted information. 

    def generate(toplevels)
      RDoc::TopLevel.all_classes_and_modules.each do |cls|
        process_class(cls)
      end
    end

    def process_class(from_class)
      generate_class_info(from_class)

      # now recure into this classes constituent classess
      from_class.each_classmodule do |mod|
        process_class(mod)
      end
    end

    def generate_class_info(cls)
      if cls === RDoc::NormalModule
        cls_desc = RI::ModuleDescription.new
      else
        cls_desc = RI::ClassDescription.new
        cls_desc.superclass  = cls.superclass
      end
      cls_desc.name        = cls.name
      cls_desc.full_name   = cls.full_name
      cls_desc.comment     = markup(cls.comment)

      cls_desc.attributes =cls.attributes.sort.map do |a|
        RI::Attribute.new(a.name, a.rw, markup(a.comment))
      end

      cls_desc.constants = cls.constants.map do |c|
        RI::Constant.new(c.name, c.value, markup(c.comment))
      end

      cls_desc.includes = cls.includes.map do |i|
        RI::IncludedModule.new(i.name)
      end

      class_methods, instance_methods = method_list(cls)

      cls_desc.class_methods = class_methods.map do |m|
        RI::MethodSummary.new(m.name)
      end
      cls_desc.instance_methods = instance_methods.map do |m|
        RI::MethodSummary.new(m.name)
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
      meth_desc = RI::MethodDescription.new
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
        RI::AliasName.new(a.name)
      end

      @ri_writer.add_method(cls_desc, meth_desc)
    end

    private

    # return a list of class and instance methods that we'll be
    # documenting

    def method_list(cls)
      list = cls.method_list
      unless @options.show_all
        list = list.find_all do |m|
          m.visibility == :public || m.force_documentation 
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


    # By default we replace existing classes with the
    # same name. If the --merge option was given, we instead
    # merge this definition into an existing class. We add
    # our methods, aliases, etc to that class, but do not
    # change the class's description.

    def update_or_replace(cls_desc)
      old_cls = nil

      if @options.merge
        rdr = RI::RiReader.new(RI::RiCache.new(@options.op_dir))

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

      if old_cls.nil?
        # no merge: simply overwrite
        @ri_writer.remove_class(cls_desc)
        @ri_writer.add_class(cls_desc)
      else
        # existing class: merge in
        old_desc = rdr.get_class(old_cls)

        old_desc.merge_in(cls_desc)
        @ri_writer.add_class(old_desc)
      end
    end
  end
end
