# frozen_string_literal: true
require_relative 'helper'

class RDocGeneratorDarkfishTest < RDoc::TestCase

  def setup
    super

    @lib_dir = "#{@pwd}/lib"
    $LOAD_PATH.unshift @lib_dir # ensure we load from this RDoc

    @options = RDoc::Options.new
    @options.option_parser = OptionParser.new

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_generator_darkfish_#{$$}"
    FileUtils.mkdir_p @tmpdir
    Dir.chdir @tmpdir
    @options.op_dir = @tmpdir
    @options.generator = RDoc::Generator::Darkfish

    $LOAD_PATH.each do |path|
      darkfish_dir = File.join path, 'rdoc/generator/template/darkfish/'
      next unless File.directory? darkfish_dir
      @options.template_dir = darkfish_dir
      break
    end

    @rdoc.options = @options

    @g = @options.generator.new @store, @options
    @rdoc.generator = @g

    @top_level = @store.add_file 'file.rb'
    @top_level.parser = RDoc::Parser::Ruby
    @klass = @top_level.add_class RDoc::NormalClass, 'Klass'

    @alias_constant = RDoc::Constant.new 'A', nil, ''
    @alias_constant.record_location @top_level

    @top_level.add_constant @alias_constant

    @klass.add_module_alias @klass, @klass.name, @alias_constant, @top_level

    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth_bang = RDoc::AnyMethod.new nil, 'method!'
    @meth_with_html_tag_yield = RDoc::AnyMethod.new nil, 'method_with_html_tag_yield'
    @meth_with_html_tag_yield.block_params = '%<<script>alert("atui")</script>>, yield_arg'
    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''

    @klass.add_method @meth
    @klass.add_method @meth_bang
    @klass.add_method @meth_with_html_tag_yield
    @klass.add_attribute @attr

    @ignored = @top_level.add_class RDoc::NormalClass, 'Ignored'
    @ignored.ignore

    @store.complete :private

    @object      = @store.find_class_or_module 'Object'
    @klass_alias = @store.find_class_or_module 'Klass::A'
  end

  def teardown
    super

    $LOAD_PATH.shift
    Dir.chdir @pwd
    FileUtils.rm_rf @tmpdir
  end

  def test_generate
    top_level = @store.add_file 'file.rb'
    top_level.add_class @klass.class, @klass.name
    @klass.add_class RDoc::NormalClass, 'Inner'
    @klass.add_comment <<~RDOC, top_level
    = Heading 1
    Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod
    == Heading 1.1
    tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
    === Heading 1.1.1
    quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
    ==== Heading 1.1.1.1
    consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
    == Heading 1.2
    cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat
    == Heading 1.3
    non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
    === Heading 1.3.1
    etc etc...
    RDOC

    @g.generate

    assert_file 'index.html'
    assert_file 'Object.html'
    assert_file 'Klass.html'
    assert_file 'Klass/Inner.html'
    assert_file 'table_of_contents.html'
    assert_file 'js/search_index.js'

    assert_hard_link 'css/rdoc.css'
    assert_hard_link 'css/fonts.css'

    assert_hard_link 'fonts/SourceCodePro-Bold.ttf'
    assert_hard_link 'fonts/SourceCodePro-Regular.ttf'

    encoding = Regexp.escape Encoding::UTF_8.name

    assert_match %r%<meta charset="#{encoding}">%, File.binread('index.html')
    assert_match %r%<meta charset="#{encoding}">%, File.binread('Object.html')

    refute_match(/Ignored/, File.binread('index.html'))
    summary = File.binread('index.html')[%r[<summary.*Klass\.html.*</summary>.*</details>]m]
    assert_match(%r[Klass/Inner\.html".*>Inner<], summary)

    klass = File.binread('Klass.html')
    klassnav = klass[%r[<div class="nav-section">.*]m]
    assert_match(
      %r[<li>\s*<details open>\s*<summary>\s*<a href=\S+>Heading 1</a>\s*</summary>\s*<ul]m,
      klassnav
    )
    assert_match(
      %r[<li>\s*<a href=\S+>Heading 1.1.1.1</a>\s*</ul>\s*</details>\s*</li>]m,
      klassnav
    )

    assert_match(/<h1 id="class-Klass-label-Heading\+1">Heading 1(?!\.)/,
                 klass[%r[<section class=\"description\">.*</section>]m])
    toc = File.binread('table_of_contents.html')
    assert_match(
      %r[<a\s+href="Klass\.html#class-Klass-label-Heading\+1">Heading 1</a>]m,
      toc[%r[<h2\s+id=\"classes\">.*(?=<h2\b)]m][%r[<a\s+href="Klass\.html".*(?=</li\b)]m]
    )
  end

  def test_generate_index_with_main_page
    top_level = @store.add_file 'file.rb'
    top_level.comment = <<~RDOC
    = Heading 1
    Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod
    == Heading 1.1
    tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
    === Heading 1.1.1
    quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
    ==== Heading 1.1.1.1
    consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
    == Heading 1.2
    cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat
    == Heading 1.3
    non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
    === Heading 1.3.1
    etc etc...
    RDOC

    @options.main_page = 'file.rb'
    @options.title = 'My awesome Ruby project'

    @g.generate

    assert_file 'index.html'
    assert_file 'table_of_contents.html'
    assert_file 'js/search_index.js'

    assert_hard_link 'css/rdoc.css'
    assert_hard_link 'css/fonts.css'

    assert_hard_link 'fonts/SourceCodePro-Bold.ttf'
    assert_hard_link 'fonts/SourceCodePro-Regular.ttf'

    index_html = File.binread('index.html')

    assert_include index_html, "<h3>Table of Contents</h3>"
    assert_include index_html, '<h1 id="label-Heading+1">Heading 1'
    # When there's a main page, the default description should not be shown
    assert_not_include index_html, 'This is the API documentation for My awesome Ruby project.'
  end

  def test_generate_index_without_main_page
    top_level = @store.add_file 'file.rb'
    top_level.comment = <<~RDOC
    = Heading 1
    Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod
    == Heading 1.1
    tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
    === Heading 1.1.1
    quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
    ==== Heading 1.1.1.1
    consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
    == Heading 1.2
    cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat
    == Heading 1.3
    non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
    === Heading 1.3.1
    etc etc...
    RDOC

    @options.title = 'My awesome Ruby project'

    @g.generate

    assert_file 'index.html'
    assert_file 'table_of_contents.html'
    assert_file 'js/search_index.js'

    assert_hard_link 'css/rdoc.css'
    assert_hard_link 'css/fonts.css'

    assert_hard_link 'fonts/SourceCodePro-Bold.ttf'
    assert_hard_link 'fonts/SourceCodePro-Regular.ttf'

    index_html = File.binread('index.html')

    # If there is no main page, the index page should not have a table of contents
    assert_not_include index_html, "<h3>Table of Contents</h3>"
    assert_include index_html, 'This is the API documentation for My awesome Ruby project.'
  end

  def test_generate_page
    @store.add_file 'outer.rdoc', parser: RDoc::Parser::Simple
    @store.add_file 'outer/inner.rdoc', parser: RDoc::Parser::Simple
    @g.generate
    assert_file 'outer_rdoc.html'
    assert_file 'outer/inner_rdoc.html'
    index = File.binread('index.html')
    re = %r[<summary><a href="\./outer_rdoc\.html">outer</a></summary>.*?</details>]m
    assert_match(re, index)
    summary = index[re]
    assert_match %r[<a href="\./outer/inner_rdoc.html">inner</a>], summary
    re = %r[<details open><summary><a href="\./outer_rdoc\.html">outer</a></summary>.*?</details>]m
    assert_match(re, File.binread('outer_rdoc.html'))
    re = %r[<details open><summary><a href="\.\./outer_rdoc\.html">outer</a></summary>.*?</details>]m
    assert_match(re, File.binread('outer/inner_rdoc.html'))
  end

  def test_generate_dry_run
    @g.dry_run = true
    top_level = @store.add_file 'file.rb'
    top_level.add_class @klass.class, @klass.name

    @g.generate

    refute_file 'index.html'
    refute_file 'Object.html'
  end

  def test_generate_static
    FileUtils.mkdir_p 'dir/images'
    FileUtils.touch 'dir/images/image.png'
    FileUtils.mkdir_p 'file'
    FileUtils.touch 'file/file.txt'

    @options.static_path = [
      File.expand_path('dir'),
      File.expand_path('file/file.txt'),
    ]

    @g.generate

    assert_file 'images/image.png'
    assert_file 'file.txt'
  end

  def test_generate_static_dry_run
    FileUtils.mkdir 'static'
    FileUtils.touch 'static/image.png'

    @options.static_path = [File.expand_path('static')]
    @g.dry_run = true

    @g.generate

    refute_file 'image.png'
  end

  def test_install_rdoc_static_file
    src = Pathname File.expand_path(__FILE__, @pwd)
    dst = File.join @tmpdir, File.basename(src)
    options = {}

    @g.install_rdoc_static_file src, dst, options

    assert_file dst
    assert_hard_link dst
  end

  def test_install_rdoc_static_file_missing
    src = Pathname(__FILE__) + 'nonexistent'
    dst = File.join @tmpdir, File.basename(src)
    options = {}

    @g.install_rdoc_static_file src, dst, options

    refute_file dst
  end

  def test_setup
    @g.setup

    assert_equal [@klass_alias, @ignored, @klass, @object],
                 @g.classes.sort_by { |klass| klass.full_name }
    assert_equal [@top_level],                           @g.files
    assert_equal [@meth, @meth, @meth_bang, @meth_bang, @meth_with_html_tag_yield, @meth_with_html_tag_yield], @g.methods
    assert_equal [@klass_alias, @klass, @object], @g.modsort
  end

  def test_template_for
    classpage = Pathname.new @options.template_dir + 'class.rhtml'

    template = @g.send(:template_for, classpage, true, RDoc::ERBIO)
    assert_kind_of RDoc::ERBIO, template

    assert_same template, @g.send(:template_for, classpage)
  end

  def test_template_for_dry_run
    classpage = Pathname.new @options.template_dir + 'class.rhtml'

    template = @g.send(:template_for, classpage, true, ERB)
    assert_kind_of ERB, template

    assert_same template, @g.send(:template_for, classpage)
  end

  def test_template_for_partial
    partial = Pathname.new @options.template_dir + '_sidebar_classes.rhtml'

    template = @g.send(:template_for, partial, false, RDoc::ERBPartial)

    assert_kind_of RDoc::ERBPartial, template

    assert_same template, @g.send(:template_for, partial)
  end

  def test_generated_method_with_html_tag_yield
    top_level = @store.add_file 'file.rb'
    top_level.add_class @klass.class, @klass.name

    @g.generate

    path = File.join @tmpdir, 'A.html'

    f = open(path)
    internal_file = f.read
    method_name_index = internal_file.index('<span class="method-name">method_with_html_tag_yield</span>')
    last_of_method_name_index = method_name_index + internal_file[method_name_index..-1].index('<div class="method-description">') - 1
    method_name = internal_file[method_name_index..last_of_method_name_index]
    f.close

    assert_includes method_name, '{ |%&lt;&lt;script&gt;alert(&quot;atui&quot;)&lt;/script&gt;&gt;, yield_arg| ... }'
  end

  def test_generated_filename_with_html_tag
    filename = '"><em>should be escaped'
    begin # in @tmpdir
      File.write(filename, '')
    rescue SystemCallError
      # ", <, > chars are prohibited as filename
      return
    else
      File.unlink(filename)
    end
    @store.add_file filename
    doc = @store.all_files.last
    doc.parser = RDoc::Parser::Simple

    @g.generate

    Dir.glob("*.html", base: @tmpdir) do |html|
      File.binread(File.join(@tmpdir, html)).scan(/.*should be escaped.*/) do |line|
        assert_not_include line, "<em>", html
      end
    end
  end

  def test_template_stylesheets
    css = Tempfile.create(%W'hoge .css', Dir.mktmpdir('tmp', '.'))
    File.write(css, '')
    css.close
    base = File.basename(css)
    refute_file(base)

    @options.template_stylesheets << css

    @g.generate

    assert_file base
    assert_include File.binread('index.html'), %Q[href="./#{base}"]
  end

  def test_html_lang
    @g.generate

    content = File.binread("index.html")
    assert_include(content, '<html lang="en">')
  end

  def test_html_lang_from_locale
    @options.locale = RDoc::I18n::Locale.new 'ja'
    @g.generate

    content = File.binread("index.html")
    assert_include(content, '<html lang="ja">')
  end

  def test_title
    title = "RDoc Test".freeze
    @options.title = title
    @g.generate

    assert_main_title(File.binread('index.html'), title)
  end

  def test_title_escape
    title = %[<script>alert("RDoc")</script>].freeze
    @options.title = title
    @g.generate

    assert_main_title(File.binread('index.html'), title)
  end

  def test_meta_tags_for_index
    @options.title = "My awesome Ruby project"
    @g.generate

    content = File.binread("index.html")

    assert_include(content, '<meta name="keywords" content="ruby,documentation,My awesome Ruby project">')
    assert_include(content, '<meta name="description" content="Documentation for My awesome Ruby project">')
  end

  def test_meta_tags_for_classes
    top_level = @store.add_file("file.rb")
    top_level.add_class(@klass.class, @klass.name)
    inner = @klass.add_class(RDoc::NormalClass, "Inner")
    inner.add_comment("This is a normal class. It is fully documented.", top_level)

    @g.generate

    content = File.binread("Klass/Inner.html")
    assert_include(content, '<meta name="keywords" content="ruby,class,Klass::Inner">')
    assert_include(
      content,
      '<meta name="description" content="class Klass::Inner: This is a normal class. It is fully documented.">',
    )
  end

  def test_meta_tags_for_rdoc_files
    top_level = @store.add_file("CONTRIBUTING.rdoc", parser: RDoc::Parser::Simple)
    top_level.comment = <<~RDOC
      = Contributing

      Here are the instructions for contributing. Begin by installing Ruby.
    RDOC

    @g.generate

    content = File.binread("CONTRIBUTING_rdoc.html")
    assert_include(content, '<meta name="keywords" content="ruby,documentation,CONTRIBUTING">')
    assert_include(
      content,
      "<meta name=\"description\" content=\"CONTRIBUTING: Contributing Here are the instructions for contributing." \
      " Begin by installing Ruby.\">",
    )
  end

  def test_meta_tags_for_markdown_files_paragraph
    top_level = @store.add_file("README.md", parser: RDoc::Parser::Simple)
    top_level.comment = <<~MARKDOWN
      # Distributed Ruby: dRuby

      dRuby is a distributed object system for Ruby.  It allows an object.
    MARKDOWN

    @g.generate

    content = File.binread("README_md.html")
    assert_include(
      content,
      "<meta name=\"description\" content=\"" \
      "README: dRuby " \
      "dRuby is a distributed object system for Ruby. " \
      "It allows an object."
    )
  end

  def test_meta_tags_for_markdown_files
    top_level = @store.add_file("MyPage.md", parser: RDoc::Parser::Markdown)
    top_level.comment = <<~MARKDOWN
      # MyPage

      This is a comment
    MARKDOWN

    @g.generate

    content = File.binread("MyPage_md.html")
    assert_include(content, '<meta name="keywords" content="ruby,documentation,MyPage">')
    assert_include(
      content,
      '<meta name="description" content="MyPage: # MyPage This is a comment">',
    )
  end

  def test_meta_tags_for_raw_pages
    top_level = @store.add_file("MyPage", parser: RDoc::Parser::Simple)
    comment = RDoc::Comment.new('this is a comment')
    comment.document = RDoc::Markup::Document.new(RDoc::Markup::Paragraph.new('this is a comment'))
    top_level.comment = comment

    @g.generate

    content = File.binread("MyPage.html")
    assert_include(content, '<meta name="keywords" content="ruby,documentation,MyPage">')
    assert_include(content, '<meta name="description" content="MyPage: this is a comment">')
  end

  def test_meta_tags_for_empty_document
    top_level = @store.add_file("MyPage", parser: RDoc::Parser::Simple)
    top_level.comment = RDoc::Comment.from_document(RDoc::Markup::Document.new)

    @g.generate

    content = File.binread("MyPage.html")
    assert_include(content, '<meta name="keywords" content="ruby,documentation,MyPage">')
    assert_include(
      content,
      '<meta name="description" content="MyPage: ">',
    )
  end

  def test_canonical_url_for_index
    @store.options.canonical_root = @options.canonical_root = "https://docs.ruby-lang.org/en/master/"
    @g.generate

    content = File.binread("index.html")

    assert_include(content, '<link rel="canonical" href="https://docs.ruby-lang.org/en/master/">')
  end

  def test_canonical_url_for_classes
    top_level = @store.add_file("file.rb")
    top_level.add_class(@klass.class, @klass.name)
    inner = @klass.add_class(RDoc::NormalClass, "Inner")

    @store.options.canonical_root = @options.canonical_root = "https://docs.ruby-lang.org/en/master/"
    @g.generate

    content = File.binread("Klass/Inner.html")

    assert_include(content, '<link rel="canonical" href="https://docs.ruby-lang.org/en/master/Klass/Inner.html">')
  end

  def test_canonical_url_for_rdoc_files
    top_level = @store.add_file("CONTRIBUTING.rdoc", parser: RDoc::Parser::Simple)

    @store.options.canonical_root = @options.canonical_root = "https://docs.ruby-lang.org/en/master/"
    @g.generate

    content = File.binread("CONTRIBUTING_rdoc.html")

    assert_include(content, '<link rel="canonical" href="https://docs.ruby-lang.org/en/master/CONTRIBUTING_rdoc.html">')
  end

  ##
  # Asserts that +filename+ has a link count greater than 1 if hard links to
  # @tmpdir are supported.

  def assert_hard_link(filename)
    assert_file filename

    src = @g.template_dir + '_head.rhtml'
    dst = File.join @tmpdir, 'hardlinktest'

    begin
      FileUtils.ln src, dst
      nlink = File.stat(dst).nlink if File.identical? src, dst
      FileUtils.rm dst
      return if nlink == 1
    rescue SystemCallError
      return
    end

    assert_operator File.stat(filename).nlink, :>, 1,
                    "#{filename} is not hard-linked"
  end

  def assert_main_title(content, title)
    title = CGI.escapeHTML(title)
    assert_equal(title, content[%r[<title>(.*?)<\/title>]im, 1])
    assert_include(content[%r[<main\s[^<>]*+>\s*(.*?)</main>]im, 1], title)
  end
end
