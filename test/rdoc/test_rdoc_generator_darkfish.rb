require 'rdoc/test_case'

class TestRDocGeneratorDarkfish < RDoc::TestCase

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

    @klass.add_module_alias @klass, 'A', @top_level

    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth_bang = RDoc::AnyMethod.new nil, 'method!'
    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''

    @klass.add_method @meth
    @klass.add_method @meth_bang
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

  def assert_file path
    assert File.file?(path), "#{path} is not a file"
  end

  def refute_file path
    refute File.exist?(path), "#{path} exists"
  end

  def mu_pp obj
    s = ''
    s = PP.pp obj, s
    s = s.force_encoding Encoding.default_external if defined? Encoding
    s.chomp
  end

  def test_generate
    top_level = @store.add_file 'file.rb'
    top_level.add_class @klass.class, @klass.name

    @g.generate

    assert_file 'index.html'
    assert_file 'Object.html'
    assert_file 'table_of_contents.html'
    assert_file 'js/search_index.js'

    encoding = if Object.const_defined? :Encoding then
                 Regexp.escape Encoding::UTF_8.name
               else
                 Regexp.escape 'UTF-8'
               end

    assert_match(/<meta content="text\/html; charset=#{encoding}"/,
                 File.read('index.html'))
    assert_match(/<meta content="text\/html; charset=#{encoding}"/,
                 File.read('Object.html'))

    refute_match(/Ignored/, File.read('index.html'))
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

  def test_setup
    @g.setup

    assert_equal [@klass_alias, @ignored, @klass, @object],
                 @g.classes.sort_by { |klass| klass.full_name }
    assert_equal [@top_level],                           @g.files
    assert_equal [@meth, @meth, @meth_bang, @meth_bang], @g.methods
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

end

