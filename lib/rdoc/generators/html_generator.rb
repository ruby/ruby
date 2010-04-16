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
require 'rdoc/markup/simple_markup/to_html'
require 'cgi'

module Generators

  # Name of sub-direcories that hold file and class/module descriptions

  FILE_DIR  = "files"
  CLASS_DIR = "classes"
  CSS_NAME  = "rdoc-style.css"


  ##
  # Build a hash of all items that can be cross-referenced.
  # This is used when we output required and included names:
  # if the names appear in this hash, we can generate
  # an html cross reference to the appropriate description.
  # We also use this when parsing comment blocks: any decorated
  # words matching an entry in this list are hyperlinked.

  class AllReferences
    @@refs = {}

    def AllReferences::reset
      @@refs = {}
    end

    def AllReferences.add(name, html_class)
      @@refs[name] = html_class
    end

    def AllReferences.[](name)
      @@refs[name]
    end

    def AllReferences.keys
      @@refs.keys
    end
  end


  ##
  # Subclass of the SM::ToHtml class that supports looking
  # up words in the AllReferences list. Those that are
  # found (like AllReferences in this comment) will
  # be hyperlinked

  class HyperlinkHtml < SM::ToHtml
    # We need to record the html path of our caller so we can generate
    # correct relative paths for any hyperlinks that we find
    def initialize(from_path, context)
      super()
      @from_path = from_path

      @parent_name = context.parent_name
      @parent_name += "::" if @parent_name
      @context = context
    end

    # We're invoked when any text matches the CROSSREF pattern
    # (defined in MarkUp). If we fine the corresponding reference,
    # generate a hyperlink. If the name we're looking for contains
    # no punctuation, we look for it up the module/class chain. For
    # example, HyperlinkHtml is found, even without the Generators::
    # prefix, because we look for it in module Generators first.

    def handle_special_CROSSREF(special)
      name = special.text
      if name[0,1] == '#'
        lookup = name[1..-1]
        name = lookup unless Options.instance.show_hash
      else
        lookup = name
      end

      # Find class, module, or method in class or module.
      if /([A-Z]\w*)[.\#](\w+[!?=]?)/ =~ lookup
        container = $1
        method = $2
        ref = @context.find_symbol(container, method)
      elsif /([A-Za-z]\w*)[.\#](\w+(\([\.\w+\*\/\+\-\=\<\>]+\))?)/ =~ lookup
        container = $1
        method = $2
        ref = @context.find_symbol(container, method)
      else
        ref = @context.find_symbol(lookup)
      end

      if ref and ref.document_self
        "<a href=\"#{ref.as_href(@from_path)}\">#{name}</a>"
      else
        name
      end
    end


    # Generate a hyperlink for url, labeled with text. Handle the
    # special cases for img: and link: described under handle_special_HYPEDLINK
    def gen_url(url, text)
      if url =~ /([A-Za-z]+):(.*)/
        type = $1
        path = $2
      else
        type = "http"
        path = url
        url  = "http://#{url}"
      end

      if type == "link"
        if path[0,1] == '#'     # is this meaningful?
          url = path
        else
          url = HTMLGenerator.gen_url(@from_path, path)
        end
      end

      if (type == "http" || type == "link") &&
          url =~ /\.(gif|png|jpg|jpeg|bmp)$/

        "<img src=\"#{url}\" />"
      else
        "<a href=\"#{url}\">#{text.sub(%r{^#{type}:/*}, '')}</a>"
      end
    end

    # And we're invoked with a potential external hyperlink mailto:
    # just gets inserted. http: links are checked to see if they
    # reference an image. If so, that image gets inserted using an
    # <img> tag. Otherwise a conventional <a href> is used.  We also
    # support a special type of hyperlink, link:, which is a reference
    # to a local file whose path is relative to the --op directory.

    def handle_special_HYPERLINK(special)
      url = special.text
      gen_url(url, url)
    end

    # HEre's a hypedlink where the label is different to the URL
    #  <label>[url]
    #

    def handle_special_TIDYLINK(special)
      text = special.text
#      unless text =~ /(\S+)\[(.*?)\]/
      unless text =~ /\{(.*?)\}\[(.*?)\]/ or text =~ /(\S+)\[(.*?)\]/
        return text
      end
      label = $1
      url   = $2
      gen_url(url, label)
    end

  end



  #####################################################################
  #
  # Handle common markup tasks for the various Html classes
  #

  module MarkUp

    # Convert a string in markup format into HTML. We keep a cached
    # SimpleMarkup object lying around after the first time we're
    # called per object.

    def markup(str, remove_para=false)
      return '' unless str
      unless defined? @markup
        @markup = SM::SimpleMarkup.new

        # class names, variable names, or instance variables
        @markup.add_special(/(
                               \w+(::\w+)*[.\#]\w+(\([\.\w+\*\/\+\-\=\<\>]+\))?  # A::B.meth(**) (for operator in Fortran95)
                             | \#\w+(\([.\w\*\/\+\-\=\<\>]+\))?  #  meth(**) (for operator in Fortran95)
                             | \b([A-Z]\w*(::\w+)*[.\#]\w+)  #    A::B.meth
                             | \b([A-Z]\w+(::\w+)*)       #    A::B..
                             | \#\w+[!?=]?                #    #meth_name
                             | \b\w+([_\/\.]+\w+)*[!?=]?  #    meth_name
                             )/x,
                            :CROSSREF)

        # external hyperlinks
        @markup.add_special(/((link:|https?:|mailto:|ftp:|www\.)\S+\w)/, :HYPERLINK)

        # and links of the form  <text>[<url>]
        @markup.add_special(/(((\{.*?\})|\b\S+?)\[\S+?\.\S+?\])/, :TIDYLINK)
#        @markup.add_special(/\b(\S+?\[\S+?\.\S+?\])/, :TIDYLINK)

      end
      unless defined? @html_formatter
        @html_formatter = HyperlinkHtml.new(self.path, self)
      end

      # Convert leading comment markers to spaces, but only
      # if all non-blank lines have them

      if str =~ /^(?>\s*)[^\#]/
        content = str
      else
        content = str.gsub(/^\s*(#+)/)  { $1.tr('#',' ') }
      end

      res = @markup.convert(content, @html_formatter)
      if remove_para
        res.sub!(/^<p>/, '')
        res.sub!(/<\/p>$/, '')
      end
      res
    end

    # Qualify a stylesheet URL; if if +css_name+ does not begin with '/' or
    # 'http[s]://', prepend a prefix relative to +path+. Otherwise, return it
    # unmodified.

    def style_url(path, css_name=nil)
#      $stderr.puts "style_url( #{path.inspect}, #{css_name.inspect} )"
      css_name ||= CSS_NAME
      if %r{^(https?:/)?/} =~ css_name
        return css_name
      else
        return HTMLGenerator.gen_url(path, css_name)
      end
    end

    # Build a webcvs URL with the given 'url' argument. URLs with a '%s' in them
    # get the file's path sprintfed into them; otherwise they're just catenated
    # together.

    def cvs_url(url, full_path)
      if /%s/ =~ url
        return sprintf( url, full_path )
      else
        return url + full_path
      end
    end
  end


  #####################################################################
  #
  # A Context is built by the parser to represent a container: contexts
  # hold classes, modules, methods, require lists and include lists.
  # ClassModule and TopLevel are the context objects we process here
  #
  class ContextUser

    include MarkUp

    attr_reader :context

    def initialize(context, options)
      @context = context
      @options = options
    end

    # convenience method to build a hyperlink
    def href(link, cls, name)
      %{<a href="#{link}" class="#{cls}">#{name}</a>} #"
    end

    # return a reference to outselves to be used as an href=
    # the form depends on whether we're all in one file
    # or in multiple files

    def as_href(from_path)
      if @options.all_one_file
        "#" + path
      else
        HTMLGenerator.gen_url(from_path, path)
      end
    end

    # Create a list of HtmlMethod objects for each method
    # in the corresponding context object. If the @options.show_all
    # variable is set (corresponding to the <tt>--all</tt> option,
    # we include all methods, otherwise just the public ones.

    def collect_methods
      list = @context.method_list
      unless @options.show_all
        list = list.find_all {|m| m.visibility == :public || m.visibility == :protected || m.force_documentation }
      end
      @methods = list.collect {|m| HtmlMethod.new(m, self, @options) }
    end

    # Build a summary list of all the methods in this context
    def build_method_summary_list(path_prefix="")
      collect_methods unless @methods
      meths = @methods.sort
      res = []
      meths.each do |meth|
	res << {
          "name" => CGI.escapeHTML(meth.name),
          "aref" => "#{path_prefix}\##{meth.aref}"
        }
      end
      res
    end


    # Build a list of aliases for which we couldn't find a
    # corresponding method
    def build_alias_summary_list(section)
      values = []
      @context.aliases.each do |al|
        next unless al.section == section
        res = {
          'old_name' => al.old_name,
          'new_name' => al.new_name,
        }
        if al.comment && !al.comment.empty?
          res['desc'] = markup(al.comment, true)
        end
        values << res
      end
      values
    end

    # Build a list of constants
    def build_constants_summary_list(section)
      values = []
      @context.constants.each do |co|
        next unless co.section == section
        res = {
          'name'  => co.name,
          'value' => CGI.escapeHTML(co.value)
        }
        res['desc'] = markup(co.comment, true) if co.comment && !co.comment.empty?
        values << res
      end
      values
    end

    def build_requires_list(context)
      potentially_referenced_list(context.requires) {|fn| [fn + ".rb"] }
    end

    def build_include_list(context)
      potentially_referenced_list(context.includes)
    end

    # Build a list from an array of <i>Htmlxxx</i> items. Look up each
    # in the AllReferences hash: if we find a corresponding entry,
    # we generate a hyperlink to it, otherwise just output the name.
    # However, some names potentially need massaging. For example,
    # you may require a Ruby file without the .rb extension,
    # but the file names we know about may have it. To deal with
    # this, we pass in a block which performs the massaging,
    # returning an array of alternative names to match

    def potentially_referenced_list(array)
      res = []
      array.each do |i|
        ref = AllReferences[i.name]
#         if !ref
#           container = @context.parent
#           while !ref && container
#             name = container.name + "::" + i.name
#             ref = AllReferences[name]
#             container = container.parent
#           end
#         end

        ref = @context.find_symbol(i.name)
        ref = ref.viewer if ref

        if !ref && block_given?
          possibles = yield(i.name)
          while !ref and !possibles.empty?
            ref = AllReferences[possibles.shift]
          end
        end
        h_name = CGI.escapeHTML(i.name)
        if ref and ref.document_self
          path = url(ref.path)
          res << { "name" => h_name, "aref" => path }
        else
          res << { "name" => h_name }
        end
      end
      res
    end

    # Build an array of arrays of method details. The outer array has up
    # to six entries, public, private, and protected for both class
    # methods, the other for instance methods. The inner arrays contain
    # a hash for each method

    def build_method_detail_list(section)
      outer = []

      methods = @methods.sort
      for singleton in [true, false]
        for vis in [ :public, :protected, :private ]
          res = []
          methods.each do |m|
            if m.section == section and
                m.document_self and
                m.visibility == vis and
                m.singleton == singleton
              row = {}
              if m.call_seq
                row["callseq"] = m.call_seq.gsub(/->/, '&rarr;')
              else
                row["name"]        = CGI.escapeHTML(m.name)
                row["params"]      = m.params
              end
              desc = m.description.strip
              row["m_desc"]      = desc unless desc.empty?
              row["aref"]        = m.aref
              row["visibility"]  = m.visibility.to_s

              alias_names = []
              m.aliases.each do |other|
                if other.viewer   # won't be if the alias is private
                  alias_names << {
                    'name' => other.name,
                    'aref'  => other.viewer.as_href(path)
                  }
                end
              end
              unless alias_names.empty?
                row["aka"] = alias_names
              end

              if @options.inline_source
                code = m.source_code
                row["sourcecode"] = code if code
              else
                code = m.src_url
                if code
                  row["codeurl"] = code
                  row["imgurl"]  = m.img_url
                end
              end
              res << row
            end
          end
          if res.size > 0
            outer << {
              "type"    => vis.to_s.capitalize,
              "category"    => singleton ? "Class" : "Instance",
              "methods" => res
            }
          end
        end
      end
      outer
    end

    # Build the structured list of classes and modules contained
    # in this context.

    def build_class_list(level, from, section, infile=nil)
      res = ""
      prefix = "&nbsp;&nbsp;::" * level;

      from.modules.sort.each do |mod|
        next unless mod.section == section
        next if infile && !mod.defined_in?(infile)
        if mod.document_self
          res <<
            prefix <<
            "Module " <<
            href(url(mod.viewer.path), "link", mod.full_name) <<
            "<br />\n" <<
            build_class_list(level + 1, mod, section, infile)
        end
      end

      from.classes.sort.each do |cls|
        next unless cls.section == section
        next if infile && !cls.defined_in?(infile)
        if cls.document_self
          res      <<
            prefix <<
            "Class " <<
            href(url(cls.viewer.path), "link", cls.full_name) <<
            "<br />\n" <<
            build_class_list(level + 1, cls, section, infile)
        end
      end

      res
    end

    def url(target)
      HTMLGenerator.gen_url(path, target)
    end

    def aref_to(target)
      if @options.all_one_file
        "#" + target
      else
        url(target)
      end
    end

    def document_self
      @context.document_self
    end

    def diagram_reference(diagram)
      res = diagram.gsub(/((?:src|href)=")(.*?)"/) {
        $1 + url($2) + '"'
      }
      res
    end


    # Find a symbol in ourselves or our parent
    def find_symbol(symbol, method=nil)
      res = @context.find_symbol(symbol, method)
      if res
        res = res.viewer
      end
      res
    end

    # create table of contents if we contain sections

    def add_table_of_sections
      toc = []
      @context.sections.each do |section|
        if section.title
          toc << {
            'secname' => section.title,
            'href'    => section.sequence
          }
        end
      end

      @values['toc'] = toc unless toc.empty?
    end


  end

  #####################################################################
  #
  # Wrap a ClassModule context

  class HtmlClass < ContextUser

    attr_reader :path

    def initialize(context, html_file, prefix, options)
      super(context, options)

      @html_file = html_file
      @is_module = context.is_module?
      @values    = {}

      context.viewer = self

      if options.all_one_file
        @path = context.full_name
      else
        @path = http_url(context.full_name, prefix)
      end

      collect_methods

      AllReferences.add(name, self)
    end

    # return the relative file name to store this class in,
    # which is also its url
    def http_url(full_name, prefix)
      path = full_name.dup
      if path['<<']
        path.gsub!(/<<\s*(\w*)/) { "from-#$1" }
      end
      File.join(prefix, path.split("::")) + ".html"
    end


    def name
      @context.full_name
    end

    def parent_name
      @context.parent.full_name
    end

    def index_name
      name
    end

    def write_on(f)
      value_hash
      template = TemplatePage.new(RDoc::Page::BODY,
                                      RDoc::Page::CLASS_PAGE,
                                      RDoc::Page::METHOD_LIST)
      template.write_html_on(f, @values)
    end

    def value_hash
      class_attribute_values
      add_table_of_sections

      @values["charset"] = @options.charset
      @values["style_url"] = style_url(path, @options.css)

      d = markup(@context.comment)
      @values["description"] = d unless d.empty?

      ml = build_method_summary_list
      @values["methods"] = ml unless ml.empty?

      il = build_include_list(@context)
      @values["includes"] = il unless il.empty?

      @values["sections"] = @context.sections.map do |section|

        secdata = {
          "sectitle" => section.title,
          "secsequence" => section.sequence,
          "seccomment" => markup(section.comment)
        }

        al = build_alias_summary_list(section)
        secdata["aliases"] = al unless al.empty?

        co = build_constants_summary_list(section)
        secdata["constants"] = co unless co.empty?

        al = build_attribute_list(section)
        secdata["attributes"] = al unless al.empty?

        cl = build_class_list(0, @context, section)
        secdata["classlist"] = cl unless cl.empty?

        mdl = build_method_detail_list(section)
        secdata["method_list"] = mdl unless mdl.empty?

        secdata
      end

      @values
    end

    def build_attribute_list(section)
      atts = @context.attributes.sort
      res = []
      atts.each do |att|
        next unless att.section == section
        if att.visibility == :public || att.visibility == :protected || @options.show_all
          entry = {
            "name"   => CGI.escapeHTML(att.name),
            "rw"     => att.rw,
            "a_desc" => markup(att.comment, true)
          }
          unless att.visibility == :public || att.visibility == :protected
            entry["rw"] << "-"
          end
          res << entry
        end
      end
      res
    end

    def class_attribute_values
      h_name = CGI.escapeHTML(name)

      @values["classmod"]  = @is_module ? "Module" : "Class"
      @values["title"]     = "#{@values['classmod']}: #{h_name}"

      c = @context
      c = c.parent while c and !c.diagram
      if c && c.diagram
        @values["diagram"] = diagram_reference(c.diagram)
      end

      @values["full_name"] = h_name

      parent_class = @context.superclass

      if parent_class
	@values["parent"] = CGI.escapeHTML(parent_class)

	if parent_name
	  lookup = parent_name + "::" + parent_class
	else
	  lookup = parent_class
	end

	parent_url = AllReferences[lookup] || AllReferences[parent_class]

	if parent_url and parent_url.document_self
	  @values["par_url"] = aref_to(parent_url.path)
	end
      end

      files = []
      @context.in_files.each do |f|
        res = {}
        full_path = CGI.escapeHTML(f.file_absolute_name)

        res["full_path"]     = full_path
        res["full_path_url"] = aref_to(f.viewer.path) if f.document_self

        if @options.webcvs
          res["cvsurl"] = cvs_url( @options.webcvs, full_path )
        end

        files << res
      end

      @values['infiles'] = files
    end

    def <=>(other)
      self.name <=> other.name
    end

  end

  #####################################################################
  #
  # Handles the mapping of a file's information to HTML. In reality,
  # a file corresponds to a +TopLevel+ object, containing modules,
  # classes, and top-level methods. In theory it _could_ contain
  # attributes and aliases, but we ignore these for now.

  class HtmlFile < ContextUser

    attr_reader :path
    attr_reader :name

    def initialize(context, options, file_dir)
      super(context, options)

      @values = {}

      if options.all_one_file
        @path = filename_to_label
      else
        @path = http_url(file_dir)
      end

      @name = @context.file_relative_name

      collect_methods
      AllReferences.add(name, self)
      context.viewer = self
    end

    def http_url(file_dir)
      File.join(file_dir, @context.file_relative_name.tr('.', '_')) +
        ".html"
    end

    def filename_to_label
      @context.file_relative_name.gsub(/%|\/|\?|\#/) {|s| '%' + ("%x" % s[0]) }
    end

    def index_name
      name
    end

    def parent_name
      nil
    end

    def value_hash
      file_attribute_values
      add_table_of_sections

      @values["charset"]   = @options.charset
      @values["href"]      = path
      @values["style_url"] = style_url(path, @options.css)

      if @context.comment
        d = markup(@context.comment)
        @values["description"] = d if d.size > 0
      end

      ml = build_method_summary_list
      @values["methods"] = ml unless ml.empty?

      il = build_include_list(@context)
      @values["includes"] = il unless il.empty?

      rl = build_requires_list(@context)
      @values["requires"] = rl unless rl.empty?

      if @options.promiscuous
        file_context = nil
      else
        file_context = @context
      end


      @values["sections"] = @context.sections.map do |section|

        secdata = {
          "sectitle" => section.title,
          "secsequence" => section.sequence,
          "seccomment" => markup(section.comment)
        }

        cl = build_class_list(0, @context, section, file_context)
        @values["classlist"] = cl unless cl.empty?

        mdl = build_method_detail_list(section)
        secdata["method_list"] = mdl unless mdl.empty?

        al = build_alias_summary_list(section)
        secdata["aliases"] = al unless al.empty?

        co = build_constants_summary_list(section)
        @values["constants"] = co unless co.empty?

        secdata
      end

      @values
    end

    def write_on(f)
      value_hash
      template = TemplatePage.new(RDoc::Page::BODY,
                                  RDoc::Page::FILE_PAGE,
                                  RDoc::Page::METHOD_LIST)
      template.write_html_on(f, @values)
    end

    def file_attribute_values
      full_path = @context.file_absolute_name
      short_name = File.basename(full_path)

      @values["title"] = CGI.escapeHTML("File: #{short_name}")

      if @context.diagram
        @values["diagram"] = diagram_reference(@context.diagram)
      end

      @values["short_name"]   = CGI.escapeHTML(short_name)
      @values["full_path"]    = CGI.escapeHTML(full_path)
      @values["dtm_modified"] = @context.file_stat.mtime.to_s

      if @options.webcvs
        @values["cvsurl"] = cvs_url( @options.webcvs, @values["full_path"] )
      end
    end

    def <=>(other)
      self.name <=> other.name
    end
  end

  #####################################################################

  class HtmlMethod
    include MarkUp

    attr_reader :context
    attr_reader :src_url
    attr_reader :img_url
    attr_reader :source_code

    @@seq = "M000000"

    @@all_methods = []

    def HtmlMethod::reset
      @@all_methods = []
    end

    def initialize(context, html_class, options)
      @context    = context
      @html_class = html_class
      @options    = options
      @@seq       = @@seq.succ
      @seq        = @@seq
      @@all_methods << self

      context.viewer = self

      if (ts = @context.token_stream)
        @source_code = markup_code(ts)
        unless @options.inline_source
          @src_url = create_source_code_file(@source_code)
          @img_url = HTMLGenerator.gen_url(path, 'source.png')
        end
      end

      AllReferences.add(name, self)
    end

    # return a reference to outselves to be used as an href=
    # the form depends on whether we're all in one file
    # or in multiple files

    def as_href(from_path)
      if @options.all_one_file
        "#" + path
      else
        HTMLGenerator.gen_url(from_path, path)
      end
    end

    def name
      @context.name
    end

    def section
      @context.section
    end

    def index_name
      "#{@context.name} (#{@html_class.name})"
    end

    def parent_name
      if @context.parent.parent
        @context.parent.parent.full_name
      else
        nil
      end
    end

    def aref
      @seq
    end

    def path
      if @options.all_one_file
	aref
      else
	@html_class.path + "#" + aref
      end
    end

    def description
      markup(@context.comment)
    end

    def visibility
      @context.visibility
    end

    def singleton
      @context.singleton
    end

    def call_seq
      cs = @context.call_seq
      if cs
        cs.gsub(/\n/, "<br />\n")
      else
        nil
      end
    end

    def params
      # params coming from a call-seq in 'C' will start with the
      # method name
      p = @context.params
      if p !~ /^\w/
        p = @context.params.gsub(/\s*\#.*/, '')
        p = p.tr("\n", " ").squeeze(" ")
        p = "(" + p + ")" unless p[0] == ?(

        if (block = @context.block_params)
         # If this method has explicit block parameters, remove any
         # explicit &block

         p.sub!(/,?\s*&\w+/, '')

          block.gsub!(/\s*\#.*/, '')
          block = block.tr("\n", " ").squeeze(" ")
          if block[0] == ?(
            block.sub!(/^\(/, '').sub!(/\)/, '')
          end
          p << " {|#{block.strip}| ...}"
        end
      end
      CGI.escapeHTML(p)
    end

    def create_source_code_file(code_body)
      meth_path = @html_class.path.sub(/\.html$/, '.src')
      File.makedirs(meth_path)
      file_path = File.join(meth_path, @seq) + ".html"

      template = TemplatePage.new(RDoc::Page::SRC_PAGE)
      File.open(file_path, "w") do |f|
        values = {
          'title'     => CGI.escapeHTML(index_name),
          'code'      => code_body,
          'style_url' => style_url(file_path, @options.css),
          'charset'   => @options.charset
        }
        template.write_html_on(f, values)
      end
      HTMLGenerator.gen_url(path, file_path)
    end

    def HtmlMethod.all_methods
      @@all_methods
    end

    def <=>(other)
      @context <=> other.context
    end

    ##
    # Given a sequence of source tokens, mark up the source code
    # to make it look purty.


    def markup_code(tokens)
      src = ""
      tokens.each do |t|
        next unless t
        #    p t.class
#        style = STYLE_MAP[t.class]
        style = case t
                when RubyToken::TkCONSTANT then "ruby-constant"
                when RubyToken::TkKW       then "ruby-keyword kw"
                when RubyToken::TkIVAR     then "ruby-ivar"
                when RubyToken::TkOp       then "ruby-operator"
                when RubyToken::TkId       then "ruby-identifier"
                when RubyToken::TkNode     then "ruby-node"
                when RubyToken::TkCOMMENT  then "ruby-comment cmt"
                when RubyToken::TkREGEXP   then "ruby-regexp re"
                when RubyToken::TkSTRING   then "ruby-value str"
                when RubyToken::TkVal      then "ruby-value"
                else
                    nil
                end

        text = CGI.escapeHTML(t.text)

        if style
          src << "<span class=\"#{style}\">#{text}</span>"
        else
          src << text
        end
      end

      add_line_numbers(src) if Options.instance.include_line_numbers
      src
    end

    # we rely on the fact that the first line of a source code
    # listing has
    #    # File xxxxx, line dddd

    def add_line_numbers(src)
      if src =~ /\A.*, line (\d+)/
        first = $1.to_i - 1
        last  = first + src.count("\n")
        size = last.to_s.length
        real_fmt = "%#{size}d: "
        fmt = " " * (size+2)
        src.gsub!(/^/) do
          res = sprintf(fmt, first)
          first += 1
          fmt = real_fmt
          res
        end
      end
    end

    def document_self
      @context.document_self
    end

    def aliases
      @context.aliases
    end

    def find_symbol(symbol, method=nil)
      res = @context.parent.find_symbol(symbol, method)
      if res
        res = res.viewer
      end
      res
    end
  end

  #####################################################################

  class HTMLGenerator

    include MarkUp

    ##
    # convert a target url to one that is relative to a given
    # path

    def HTMLGenerator.gen_url(path, target)
      from          = File.dirname(path)
      to, to_file   = File.split(target)

      from = from.split("/")
      to   = to.split("/")

      while from.size > 0 and to.size > 0 and from[0] == to[0]
        from.shift
        to.shift
      end

      from.fill("..")
      from.concat(to)
      from << to_file
      File.join(*from)
    end

    # Generators may need to return specific subclasses depending
    # on the options they are passed. Because of this
    # we create them using a factory

    def HTMLGenerator.for(options)
      AllReferences::reset
      HtmlMethod::reset

      if options.all_one_file
        HTMLGeneratorInOne.new(options)
      else
        HTMLGenerator.new(options)
      end
    end

    class <<self
      protected :new
    end

    # Set up a new HTML generator. Basically all we do here is load
    # up the correct output temlate

    def initialize(options) #:not-new:
      @options    = options
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
      gen_sub_directories()
      build_indices
      generate_html
    end

    private

    ##
    # Load up the HTML template specified in the options.
    # If the template name contains a slash, use it literally
    #
    def load_html_template
      template = @options.template
      unless template =~ %r{/|\\}
        template = File.join("rdoc/generators/template",
                             @options.generator.key, template)
      end
      require template
      extend RDoc::Page
    rescue LoadError
      $stderr.puts "Could not find HTML template '#{template}'"
      exit 99
    end

    ##
    # Write out the style sheet used by the main frames
    #

    def write_style_sheet
      template = TemplatePage.new(RDoc::Page::STYLE)
      unless @options.css
        File.open(CSS_NAME, "w") do |f|
          values = { "fonts" => RDoc::Page::FONTS }
          template.write_html_on(f, values)
        end
      end
    end

    ##
    # See the comments at the top for a description of the
    # directory structure

    def gen_sub_directories
      File.makedirs(FILE_DIR, CLASS_DIR)
    rescue
      $stderr.puts $!.message
      exit 1
    end

    ##
    # Generate:
    #
    # * a list of HtmlFile objects for each TopLevel object.
    # * a list of HtmlClass objects for each first level
    #   class or module in the TopLevel objects
    # * a complete list of all hyperlinkable terms (file,
    #   class, module, and method names)

    def build_indices

      @toplevels.each do |toplevel|
        @files << HtmlFile.new(toplevel, @options, FILE_DIR)
      end

      RDoc::TopLevel.all_classes_and_modules.each do |cls|
        build_class_list(cls, @files[0], CLASS_DIR)
      end
    end

    def build_class_list(from, html_file, class_dir)
      @classes << HtmlClass.new(from, html_file, class_dir, @options)
      from.each_classmodule do |mod|
        build_class_list(mod, html_file, class_dir)
      end
    end

    ##
    # Generate all the HTML
    #
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
      list.each do |item|
        if item.document_self
          op_file = item.path
          File.makedirs(File.dirname(op_file))
          File.open(op_file, "w") { |file| item.write_on(file) }
        end
      end

    end

    def gen_file_index
      gen_an_index(@files, 'Files',
                   RDoc::Page::FILE_INDEX,
                   "fr_file_index.html")
    end

    def gen_class_index
      gen_an_index(@classes, 'Classes',
                   RDoc::Page::CLASS_INDEX,
                   "fr_class_index.html")
    end

    def gen_method_index
      gen_an_index(HtmlMethod.all_methods, 'Methods',
                   RDoc::Page::METHOD_INDEX,
                   "fr_method_index.html")
    end


    def gen_an_index(collection, title, template, filename)
      template = TemplatePage.new(RDoc::Page::FR_INDEX_BODY, template)
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

      File.open(filename, "w") do |f|
        template.write_html_on(f, values)
      end
    end

    # The main index page is mostly a template frameset, but includes
    # the initial page. If the <tt>--main</tt> option was given,
    # we use this as our main page, otherwise we use the
    # first file specified on the command line.

    def gen_main_index
      template = TemplatePage.new(RDoc::Page::INDEX)
      File.open("index.html", "w") do |f|
        values = {
          "initial_page" => main_url,
          'title'        => CGI.escapeHTML(@options.title),
          'charset'      => @options.charset
        }
        if @options.inline_source
          values['inline_source'] = true
        end
        template.write_html_on(f, values)
      end
    end

    # return the url of the main page
    def main_url
      main_page = @options.main_page
      ref = nil
      if main_page
        ref = AllReferences[main_page]
        if ref
          ref = ref.path
        else
          $stderr.puts "Could not find main page #{main_page}"
        end
      end

      unless ref
        for file in @files
          if file.document_self
            ref = file.path
            break
          end
        end
      end

      unless ref
        $stderr.puts "Couldn't find anything to document"
        $stderr.puts "Perhaps you've used :stopdoc: in all classes"
        exit(1)
      end

      ref
    end


  end


  ######################################################################


  class HTMLGeneratorInOne < HTMLGenerator

    def initialize(*args)
      super
    end

    ##
    # Build the initial indices and output objects
    # based on an array of TopLevel objects containing
    # the extracted information.

    def generate(info)
      @toplevels  = info
      @files      = []
      @classes    = []
      @hyperlinks = {}

      build_indices
      generate_xml
    end


    ##
    # Generate:
    #
    # * a list of HtmlFile objects for each TopLevel object.
    # * a list of HtmlClass objects for each first level
    #   class or module in the TopLevel objects
    # * a complete list of all hyperlinkable terms (file,
    #   class, module, and method names)

    def build_indices

      @toplevels.each do |toplevel|
        @files << HtmlFile.new(toplevel, @options, FILE_DIR)
      end

      RDoc::TopLevel.all_classes_and_modules.each do |cls|
        build_class_list(cls, @files[0], CLASS_DIR)
      end
    end

    def build_class_list(from, html_file, class_dir)
      @classes << HtmlClass.new(from, html_file, class_dir, @options)
      from.each_classmodule do |mod|
        build_class_list(mod, html_file, class_dir)
      end
    end

    ##
    # Generate all the HTML. For the one-file case, we generate
    # all the information in to one big hash
    #
    def generate_xml
      values = {
        'charset' => @options.charset,
        'files'   => gen_into(@files),
        'classes' => gen_into(@classes),
        'title'        => CGI.escapeHTML(@options.title),
      }

      # this method is defined in the template file
      write_extra_pages if defined? write_extra_pages

      template = TemplatePage.new(RDoc::Page::ONE_PAGE)

      if @options.op_name
        opfile = File.open(@options.op_name, "w")
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
      gen_an_index(HtmlMethod.all_methods, 'Methods')
    end


    def gen_an_index(collection, title)
      res = []
      collection.sort.each do |f|
        if f.document_self
          res << { "href" => f.path, "name" => f.index_name }
        end
      end

      return {
        "entries" => res,
        'list_title' => title,
        'index_url'  => main_url,
      }
    end

  end
end
