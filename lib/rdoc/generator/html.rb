require 'fileutils'

require 'rdoc/generator'
require 'rdoc/markup/to_html'

##
# We're responsible for generating all the HTML files from the object tree
# defined in code_objects.rb. We generate:
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
# Method descriptions appear in whatever entity (file, class, or module) that
# contains them.
#
# We generate files in a structure below a specified subdirectory, normally
# +doc+.
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

class RDoc::Generator::HTML

  include RDoc::Generator::MarkUp

  ##
  # Generator may need to return specific subclasses depending on the
  # options they are passed. Because of this we create them using a factory

  def self.for(options)
    RDoc::Generator::AllReferences.reset
    RDoc::Generator::Method.reset

    if options.all_one_file
      RDoc::Generator::HTMLInOne.new options
    else
      new options
    end
  end

  class << self
    protected :new
  end

  ##
  # Set up a new HTML generator. Basically all we do here is load up the
  # correct output temlate

  def initialize(options) #:not-new:
    @options = options
    load_html_template
    @main_page_path = nil
  end

  ##
  # Build the initial indices and output objects
  # based on an array of TopLevel objects containing
  # the extracted information.

  def generate(toplevels)
    @toplevels  = toplevels
    @files      = []
    @classes    = []

    write_style_sheet
    gen_sub_directories
    build_indices
    generate_html
  end

  private

  ##
  # Load up the HTML template specified in the options.
  # If the template name contains a slash, use it literally

  def load_html_template
    template = @options.template

    unless template =~ %r{/|\\} then
      template = File.join('rdoc', 'generator', @options.generator.key,
                           template)
    end

    require template

    @template = self.class.const_get @options.template.upcase
    @options.template_class = @template

  rescue LoadError
    $stderr.puts "Could not find HTML template '#{template}'"
    exit 99
  end

  ##
  # Write out the style sheet used by the main frames

  def write_style_sheet
    return unless @template.constants.include? :STYLE or
                  @template.constants.include? 'STYLE'

    template = RDoc::TemplatePage.new @template::STYLE

    unless @options.css then
      open RDoc::Generator::CSS_NAME, 'w' do |f|
        values = {}

        if @template.constants.include? :FONTS or
           @template.constants.include? 'FONTS' then
          values["fonts"] = @template::FONTS
        end

        template.write_html_on(f, values)
      end
    end
  end

  ##
  # See the comments at the top for a description of the directory structure

  def gen_sub_directories
    FileUtils.mkdir_p RDoc::Generator::FILE_DIR
    FileUtils.mkdir_p RDoc::Generator::CLASS_DIR
  rescue
    $stderr.puts $!.message
    exit 1
  end

  def build_indices
    @files, @classes = RDoc::Generator::Context.build_indicies(@toplevels,
                                                               @options)
  end

  ##
  # Generate all the HTML

  def generate_html
    # the individual descriptions for files and classes
    gen_into(@files)
    gen_into(@classes)

    # and the index files
    gen_file_index
    gen_class_index
    gen_method_index
    gen_main_index

    # this method is defined in the template file
    write_extra_pages if defined? write_extra_pages
  end

  def gen_into(list)
    @file_list ||= index_to_links @files
    @class_list ||= index_to_links @classes
    @method_list ||= index_to_links RDoc::Generator::Method.all_methods

    list.each do |item|
      next unless item.document_self

      op_file = item.path

      FileUtils.mkdir_p File.dirname(op_file)

      open op_file, 'w' do |io|
        item.write_on io, @file_list, @class_list, @method_list
      end
    end
  end

  def gen_file_index
    gen_an_index @files, 'Files', @template::FILE_INDEX, "fr_file_index.html"
  end

  def gen_class_index
    gen_an_index(@classes, 'Classes', @template::CLASS_INDEX,
                 "fr_class_index.html")
  end

  def gen_method_index
    gen_an_index(RDoc::Generator::Method.all_methods, 'Methods',
                 @template::METHOD_INDEX, "fr_method_index.html")
  end

  def gen_an_index(collection, title, template, filename)
    template = RDoc::TemplatePage.new @template::FR_INDEX_BODY, template
    res = []
    collection.sort.each do |f|
      if f.document_self
        res << { "href" => f.path, "name" => f.index_name }
      end
    end

    values = {
      "entries"    => res,
      'list_title' => CGI.escapeHTML(title),
      'index_url'  => main_url,
      'charset'    => @options.charset,
      'style_url'  => style_url('', @options.css),
    }

    open filename, 'w' do |f|
      template.write_html_on(f, values)
    end
  end

  ##
  # The main index page is mostly a template frameset, but includes the
  # initial page. If the <tt>--main</tt> option was given, we use this as
  # our main page, otherwise we use the first file specified on the command
  # line.

  def gen_main_index
    if @template.const_defined? :FRAMELESS then
      main = @files.find do |file|
        @main_page == file.name
      end

      if main.nil? then
        main = @classes.find do |klass|
          main_page == klass.context.full_name
        end
      end
    else
      main = RDoc::TemplatePage.new @template::INDEX
    end

    open 'index.html', 'w'  do |f|
      style_url = style_url '', @options.css

      classes = @classes.sort.map { |klass| klass.value_hash }

      values = {
        'main_page'     => @main_page,
        'initial_page'  => main_url,
        'style_url'     => style_url('', @options.css),
        'title'         => CGI.escapeHTML(@options.title),
        'charset'       => @options.charset,
        'classes'       => classes,
      }

      values['inline_source'] = @options.inline_source

      if main.respond_to? :write_on then
        main.write_on f, @file_list, @class_list, @method_list, values
      else
        main.write_html_on f, values
      end
    end
  end

  def index_to_links(collection)
    collection.sort.map do |f|
      next unless f.document_self
      { "href" => f.path, "name" => f.index_name }
    end.compact
  end

  ##
  # Returns the url of the main page

  def main_url
    @main_page = @options.main_page
    @main_page_ref = nil

    if @main_page then
      @main_page_ref = RDoc::Generator::AllReferences[@main_page]

      if @main_page_ref then
        @main_page_path = @main_page_ref.path
      else
        $stderr.puts "Could not find main page #{@main_page}"
      end
    end

    unless @main_page_path then
      file = @files.find { |context| context.document_self }
      @main_page_path = file.path if file
    end

    unless @main_page_path then
      $stderr.puts "Couldn't find anything to document"
      $stderr.puts "Perhaps you've used :stopdoc: in all classes"
      exit 1
    end

    @main_page_path
  end

end

class RDoc::Generator::HTMLInOne < RDoc::Generator::HTML

  def initialize(*args)
    super
  end

  ##
  # Build the initial indices and output objects
  # based on an array of TopLevel objects containing
  # the extracted information.

  def generate(info)
    @toplevels  = info
    @hyperlinks = {}

    build_indices
    generate_xml
  end

  ##
  # Generate:
  #
  # * a list of RDoc::Generator::File objects for each TopLevel object.
  # * a list of RDoc::Generator::Class objects for each first level
  #   class or module in the TopLevel objects
  # * a complete list of all hyperlinkable terms (file,
  #   class, module, and method names)

  def build_indices
    @files, @classes = RDoc::Generator::Context.build_indices(@toplevels,
                                                              @options)
  end

  ##
  # Generate all the HTML. For the one-file case, we generate
  # all the information in to one big hash

  def generate_xml
    values = {
      'charset' => @options.charset,
      'files'   => gen_into(@files),
      'classes' => gen_into(@classes),
      'title'        => CGI.escapeHTML(@options.title),
    }

    # this method is defined in the template file
    write_extra_pages if defined? write_extra_pages

    template = RDoc::TemplatePage.new @template::ONE_PAGE

    if @options.op_name
      opfile = open @options.op_name, 'w'
    else
      opfile = $stdout
    end
    template.write_html_on(opfile, values)
  end

  def gen_into(list)
    res = []
    list.each do |item|
      res << item.value_hash
    end
    res
  end

  def gen_file_index
    gen_an_index(@files, 'Files')
  end

  def gen_class_index
    gen_an_index(@classes, 'Classes')
  end

  def gen_method_index
    gen_an_index(RDoc::Generator::Method.all_methods, 'Methods')
  end

  def gen_an_index(collection, title)
    return {
      "entries" => index_to_links(collection),
      'list_title' => title,
      'index_url'  => main_url,
    }
  end

end

