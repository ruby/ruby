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
    #
    # If the template is not a path, first look for it
    # in rdoc's HTML template directory.  Perhaps this behavior should
    # be reversed (first try to include the template and, only if that
    # fails, try to include it in the default template directory).
    # One danger with reversing the behavior, however, is that
    # if something like require 'html' could load up an
    # unrelated file in the standard library or in a gem.
    #
    template = @options.template

    unless template =~ %r{/|\\} then
      template = File.join('rdoc', 'generator', @options.generator.key,
                           template)
    end

    begin
      require template

      @template = self.class.const_get @options.template.upcase
      @options.template_class = @template
    rescue LoadError => e
      #
      # The template did not exist in the default template directory, so
      # see if require can find the template elsewhere (in a gem, for
      # instance).
      #
      if(e.message[template] && template != @options.template)
        template = @options.template
        retry
      end

      $stderr.puts "Could not find HTML template '#{template}': #{e.message}"
      exit 99
    end
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
    @files, @classes = RDoc::Generator::Context.build_indices(@toplevels,
                                                              @options)
  end

  ##
  # Generate all the HTML

  def generate_html
    @main_url = main_url

    # the individual descriptions for files and classes
    gen_into(@files)
    gen_into(@classes)

    # and the index files
    gen_file_index
    gen_class_index
    gen_method_index
    gen_main_index

    # this method is defined in the template file
    values = {
      'title_suffix' => CGI.escapeHTML("[#{@options.title}]"),
      'charset'      => @options.charset,
      'style_url'    => style_url('', @options.css),
    }

    @template.write_extra_pages(values) if @template.respond_to?(:write_extra_pages)
  end

  def gen_into(list)
    #
    # The file, class, and method lists technically should be regenerated
    # for every output file, in order that the relative links be correct
    # (we are worried here about frameless templates, which need this
    # information for every generated page).  Doing this is a bit slow,
    # however.  For a medium-sized gem, this increased rdoc's runtime by
    # about 5% (using the 'time' command-line utility).  While this is not
    # necessarily a problem, I do not want to pessimize rdoc for large
    # projects, however, and so we only regenerate the lists when the
    # directory of the output file changes, which seems like a reasonable
    # optimization.
    #
    file_list = {}
    class_list = {}
    method_list = {}
    prev_op_dir = nil

    list.each do |item|
      next unless item.document_self

      op_file = item.path
      op_dir = File.dirname(op_file)

      if(op_dir != prev_op_dir)
        file_list = index_to_links op_file, @files
        class_list = index_to_links op_file, @classes
        method_list = index_to_links op_file, RDoc::Generator::Method.all_methods
      end
      prev_op_dir = op_dir

      FileUtils.mkdir_p op_dir

      open op_file, 'w' do |io|
        item.write_on io, file_list, class_list, method_list
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
      'title'      => CGI.escapeHTML("#{title} [#{@options.title}]"),
      'list_title' => CGI.escapeHTML(title),
      'index_url'  => @main_url,
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
      #
      # If we're using a template without frames, then just redirect
      # to it from index.html.
      #
      # One alternative to this, expanding the main page's template into
      # index.html, is tricky because the relative URLs will be different
      # (since index.html is located in at the site's root,
      # rather than within a files or a classes subdirectory).
      #
      open 'index.html', 'w'  do |f|
        f.puts(%{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
               "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">})
        f.puts(%{<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en"
                lang="en">})
        f.puts(%{<head>})
        f.puts(%{<title>#{CGI.escapeHTML(@options.title)}</title>})
        f.puts(%{<meta http-equiv="refresh" content="0; url=#{@main_url}" />})
        f.puts(%{</head>})
        f.puts(%{<body></body>})
        f.puts(%{</html>})
      end
    else
      main = RDoc::TemplatePage.new @template::INDEX

      open 'index.html', 'w'  do |f|
        style_url = style_url '', @options.css

        classes = @classes.sort.map { |klass| klass.value_hash }

        values = {
          'initial_page'  => @main_url,
          'style_url'     => style_url('', @options.css),
          'title'         => CGI.escapeHTML(@options.title),
          'charset'       => @options.charset,
          'classes'       => classes,
        }

        values['inline_source'] = @options.inline_source

        main.write_html_on f, values
      end
    end
  end

  def index_to_links(output_path, collection)
    collection.sort.map do |f|
      next unless f.document_self
      { "href" => RDoc::Markup::ToHtml.gen_relative_url(output_path, f.path),
        "name" => f.index_name }
    end.compact
  end

  ##
  # Returns the url of the main page

  def main_url
    main_page = @options.main_page

    #
    # If a main page has been specified (--main), then search for it
    # in the AllReferences array.  This allows either files or classes
    # to be used for the main page.
    #
    if main_page then
      main_page_ref = RDoc::Generator::AllReferences[main_page]

      if main_page_ref then
        return main_page_ref.path
      else
        $stderr.puts "Could not find main page #{main_page}"
      end
    end

    #
    # No main page has been specified, so just use the README.
    #
    @files.each do |file|
      if file.name =~ /^README/ then
        return file.path
      end
    end

    #
    # There's no README (shame! shame!).  Just use the first file
    # that will be documented.
    #
    @files.each do |file|
      if file.document_self then
        return file.path
      end
    end

    #
    # There are no files to be documented...  Something seems very wrong.
    #
    raise RDoc::Error, "Couldn't find anything to document (perhaps :stopdoc: has been used in all classes)!"
  end
  private :main_url

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
      'title'   => CGI.escapeHTML(@options.title),
    }

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
end
