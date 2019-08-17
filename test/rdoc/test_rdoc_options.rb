# frozen_string_literal: true
require_relative 'helper'

class TestRDocOptions < RDoc::TestCase

  def setup
    super

    @options = RDoc::Options.new
    @generators = RDoc::RDoc::GENERATORS.dup
  end

  def teardown
    super

    RDoc::RDoc::GENERATORS.replace @generators
  end

  def test_check_files
    skip "assumes UNIX permission model" if /mswin|mingw/ =~ RUBY_PLATFORM
    skip "assumes that euid is not root" if Process.euid == 0

    out, err = capture_output do
      temp_dir do
        FileUtils.touch 'unreadable'
        FileUtils.chmod 0, 'unreadable'

        @options.files = %w[nonexistent unreadable]

        @options.check_files
      end
    end

    assert_empty @options.files

    assert_empty out
    assert_empty err
  end

  def test_check_files_warn
    @options.verbosity = 2

    out, err = verbose_capture_output do
      @options.files = %w[nonexistent]

      @options.check_files
    end

    assert_empty out
    assert_equal "file 'nonexistent' not found\n", err
    assert_empty @options.files
  end

  def test_dry_run_default
    refute @options.dry_run
  end

  def test_encode_with
    coder = {}
    class << coder; alias add []=; end

    @options.encode_with coder

    encoding = 'UTF-8'

    expected = {
      'charset'              => 'UTF-8',
      'encoding'             => encoding,
      'exclude'              => %w[~\z \.orig\z \.rej\z \.bak\z \.gemspec\z],
      'hyperlink_all'        => false,
      'line_numbers'         => false,
      'locale'               => nil,
      'locale_dir'           => 'locale',
      'locale_name'          => nil,
      'main_page'            => nil,
      'markup'               => 'rdoc',
      'output_decoration'    => true,
      'page_dir'             => nil,
      'rdoc_include'         => [],
      'show_hash'            => false,
      'static_path'          => [],
      'tab_width'            => 8,
      'template_stylesheets' => [],
      'title'                => nil,
      'visibility'           => :protected,
      'webcvs'               => nil,
    }

    assert_equal expected, coder
  end

  def test_encode_with_trim_paths
    subdir = nil
    coder = {}
    class << coder; alias add []=; end

    temp_dir do |dir|
      FileUtils.mkdir 'project'
      FileUtils.mkdir 'dir'
      FileUtils.touch 'file'

      Dir.chdir 'project' do
        subdir = File.expand_path 'subdir'
        FileUtils.mkdir 'subdir'
        @options.parse %w[
          --copy subdir
          --copy ../file
          --copy ../
          --copy /
          --include subdir
          --include ../dir
          --include ../
          --include /
        ]

        @options.encode_with coder
      end
    end

    assert_equal [subdir], coder['rdoc_include']

    assert_equal [subdir], coder['static_path']
  end

  def test_encoding_default
    assert_equal Encoding::UTF_8, @options.encoding
  end

  def test_generator_descriptions
    # HACK autotest/isolate should take care of this
    RDoc::RDoc::GENERATORS.clear
    RDoc::RDoc::GENERATORS['darkfish'] = RDoc::Generator::Darkfish
    RDoc::RDoc::GENERATORS['ri']       = RDoc::Generator::RI

    expected = <<-EXPECTED.chomp
  darkfish - HTML generator, written by Michael Granger
  ri       - creates ri data files
    EXPECTED

    assert_equal expected, @options.generator_descriptions
  end

  def test_init_with_encoding
    RDoc.load_yaml

    @options.encoding = Encoding::IBM437

    options = YAML.load YAML.dump @options

    assert_equal Encoding::IBM437, options.encoding
  end

  def test_init_with_trim_paths
    RDoc.load_yaml

    yaml = <<-YAML
--- !ruby/object:RDoc::Options
static_path:
- /etc
rdoc_include:
- /etc
    YAML

    options = YAML.load yaml

    assert_empty options.rdoc_include
    assert_empty options.static_path
  end

  def test_parse_copy_files_file_relative
    file = File.basename __FILE__
    expected = File.expand_path __FILE__

    Dir.chdir File.expand_path('..', __FILE__) do
      @options.parse %W[--copy-files #{file}]

      assert_equal [expected], @options.static_path
    end
  end

  def test_parse_copy_files_file_absolute
    @options.parse %W[--copy-files #{File.expand_path __FILE__}]

    assert_equal [File.expand_path(__FILE__)], @options.static_path
  end

  def test_parse_copy_files_directory_relative
    @options.parse %w[--copy-files .]

    assert_equal [@pwd], @options.static_path
  end

  def test_parse_copy_files_directory_absolute
    @options.parse %w[--copy-files /]

    assert_equal 1, @options.static_path.length

    assert_match %r%^([A-Z]:)?/$%i, @options.static_path.first
  end

  def test_parse_coverage
    @options.parse %w[--dcov]

    assert @options.coverage_report
    assert @options.force_update
  end

  def test_parse_coverage_no
    @options.parse %w[--no-dcov]

    refute @options.coverage_report
  end

  def test_parse_coverage_level_1
    @options.parse %w[--dcov=1]

    assert_equal 1, @options.coverage_report
  end

  def test_parse_dash_p
    out, err = capture_output do
      @options.parse %w[-p]
    end

    assert @options.pipe
    refute_match %r%^Usage: %, err
    refute_match %r%^invalid options%, err

    assert_empty out
  end

  def test_parse_dash_p_files
    out, err = capture_output do
      @options.parse ['-p', File.expand_path(__FILE__)]
    end

    refute @options.pipe
    refute_match %r%^Usage: %, err
    assert_match %r%^invalid options: -p .with files.%, err

    assert_empty out
  end

  def test_parse_default
    @options.parse []

    assert_equal RDoc::Generator::Darkfish,             @options.generator
    assert_equal 'darkfish',                            @options.template
    assert_match %r%rdoc/generator/template/darkfish$%, @options.template_dir
  end

  def test_parse_deprecated
    dep_hash = RDoc::Options::DEPRECATED
    options = dep_hash.keys.sort

    out, err = capture_output do
      @options.parse options
    end

    dep_hash.each_pair do |opt, message|
      assert_match %r%.*#{opt}.+#{message}%, err
    end

    assert_empty out
  end

  def test_parse_dry_run
    @options.parse %w[--dry-run]

    assert @options.dry_run
  end

  def test_parse_encoding
    @options.parse %w[--encoding Big5]

    assert_equal Encoding::Big5, @options.encoding
    assert_equal 'Big5',         @options.charset
  end

  def test_parse_encoding_invalid
    out, err = capture_output do
      @options.parse %w[--encoding invalid]
    end

    assert_match %r%^invalid options: --encoding invalid%, err

    assert_empty out
  end

  def test_parse_formatter
    e = assert_raise OptionParser::InvalidOption do
      @options.parse %w[--format darkfish --format ri]
    end

    assert_equal 'invalid option: --format generator already set to darkfish',
                 e.message
  end

  def test_parse_formatter_ri
    e = assert_raise OptionParser::InvalidOption do
      @options.parse %w[--format darkfish --ri]
    end

    assert_equal 'invalid option: --ri generator already set to darkfish',
                 e.message

    @options = RDoc::Options.new

    e = assert_raise OptionParser::InvalidOption do
      @options.parse %w[--format darkfish -r]
    end

    assert_equal 'invalid option: -r generator already set to darkfish',
                 e.message
  end

  def test_parse_formatter_ri_site
    e = assert_raise OptionParser::InvalidOption do
      @options.parse %w[--format darkfish --ri-site]
    end

    assert_equal 'invalid option: --ri-site generator already set to darkfish',
                 e.message

    @options = RDoc::Options.new

    e = assert_raise OptionParser::InvalidOption do
      @options.parse %w[--format darkfish -R]
    end

    assert_equal 'invalid option: -R generator already set to darkfish',
                 e.message
  end

  def test_parse_h
    out, = capture_output do
      begin
        @options.parse %w[-h]
      rescue SystemExit
      end
    end

    assert_equal 1, out.scan(/HTML generator options:/).length
    assert_equal 1, out.scan(/ri generator options:/).  length
  end

  def test_parse_help
    out, = capture_output do
      begin
        @options.parse %w[--help]
      rescue SystemExit
      end
    end

    assert_equal 1, out.scan(/HTML generator options:/).length
    assert_equal 1, out.scan(/ri generator options:/).  length
  end

  def test_parse_help_extra_generator
    RDoc::RDoc::GENERATORS['test'] = Class.new do
      def self.setup_options options
        op = options.option_parser

        op.separator 'test generator options:'
      end
    end

    out, = capture_output do
      begin
        @options.parse %w[--help]
      rescue SystemExit
      end
    end

    assert_equal 1, out.scan(/HTML generator options:/).length
    assert_equal 1, out.scan(/ri generator options:/).  length
    assert_equal 1, out.scan(/test generator options:/).length
  end

  def test_parse_format_for_extra_generator
    RDoc::RDoc::GENERATORS['test'] = Class.new do
      def self.setup_options options
        op = options.option_parser

        op.separator 'test generator options:'
      end
    end

    @options.setup_generator 'test'

    assert_equal @options.generator_name, 'test'
  end

  def test_parse_ignore_invalid
    out, err = capture_output do
      @options.parse %w[--ignore-invalid --bogus]
    end

    refute_match %r%^Usage: %, err
    assert_match %r%^invalid options: --bogus%, err

    assert_empty out
  end

  def test_parse_ignore_invalid_default
    out, err = capture_output do
      @options.parse %w[--bogus --main BLAH]
    end

    refute_match %r%^Usage: %, err
    assert_match %r%^invalid options: --bogus%, err

    assert_equal 'BLAH', @options.main_page

    assert_empty out
  end

  def test_parse_ignore_invalid_no
    out, err = capture_output do
      assert_raise SystemExit do
        @options.parse %w[--no-ignore-invalid --bogus=arg --bobogus --visibility=extended]
      end
    end

    assert_match %r%^Usage: %, err
    assert_match %r%^invalid options: --bogus=arg, --bobogus, --visibility=extended%, err

    assert_empty out
  end

  def test_parse_ignore_invalid_no_quiet
    out, err = capture_output do
      assert_raise SystemExit do
        @options.parse %w[--quiet --no-ignore-invalid --bogus=arg --bobogus --visibility=extended]
      end
    end

    refute_match %r%^Usage: %, err
    assert_match %r%^invalid options: --bogus=arg, --bobogus, --visibility=extended%, err

    assert_empty out
  end

  def test_ignore_needless_arg
    out, err = capture_output do
      @options.parse %w[--ri=foo]
    end

    assert_match %r%^invalid options: --ri=foo%, err

    assert_empty out
  end

  def test_ignore_missing_arg
    out, err = capture_output do
      @options.parse %w[--copy-files]
    end

    assert_match %r%^invalid options: --copy-files%, err

    assert_empty out
  end

  def test_parse_main
    out, err = capture_output do
      @options.parse %w[--main MAIN]
    end

    assert_empty out
    assert_empty err

    assert_equal 'MAIN', @options.main_page
  end

  def test_parse_markup
    out, err = capture_output do
      @options.parse %w[--markup tomdoc]
    end

    assert_empty out
    assert_empty err

    assert_equal 'tomdoc', @options.markup
  end

  def test_parse_page_dir
    assert_nil @options.page_dir

    out, err = capture_output do
      @options.parse %W[--page-dir #{Dir.tmpdir}]
    end

    assert_empty out
    assert_empty err

    expected =
      Pathname(Dir.tmpdir).expand_path.relative_path_from @options.root

    assert_equal expected,     @options.page_dir
    assert_equal [Dir.tmpdir], @options.files
  end

  def test_parse_page_dir_root
    assert_nil @options.page_dir

    Dir.mktmpdir do |dir|
      abs_root     = dir
      abs_page_dir = File.join dir, 'pages'
      FileUtils.mkdir abs_page_dir

      out, err = capture_output do
        @options.parse %W[--page-dir #{abs_page_dir} --root #{abs_root}]
      end

      assert_empty out
      assert_empty err

      assert_equal Pathname('pages'), @options.page_dir
      assert_equal [abs_page_dir],    @options.files
    end
  end

  def test_parse_ri_site
    @options.parse %w[--ri-site]

    assert_equal RDoc::Generator::RI,      @options.generator
    assert_equal RDoc::RI::Paths.site_dir, @options.op_dir
  end

  def test_parse_root
    assert_equal Pathname(Dir.pwd), @options.root

    out, err = capture_output do
      @options.parse %W[--root #{Dir.tmpdir}]
    end

    assert_empty out
    assert_empty err

    assert_equal Pathname(Dir.tmpdir), @options.root
    assert_includes @options.rdoc_include, @options.root.to_s
  end

  def test_parse_tab_width
    @options.parse %w[--tab-width=1]
    assert_equal 1, @options.tab_width

    @options.parse %w[-w2]
    assert_equal 2, @options.tab_width

    _, err = capture_output do
      @options.parse %w[-w=2]
    end

    assert_match 'invalid options', err

    _, err = capture_output do
      @options.parse %w[-w0]
    end

    assert_match 'invalid options', err
  end

  def test_parse_template
    out, err = capture_output do
      @options.parse %w[--template darkfish]
    end

    assert_empty out
    assert_empty err

    assert_equal 'darkfish', @options.template

    assert_match %r%rdoc/generator/template/darkfish$%, @options.template_dir
  end

  def test_parse_template_nonexistent
    out, err = capture_output do
      @options.parse %w[--template NONEXISTENT]
    end

    assert_empty out
    assert_equal "could not find template NONEXISTENT\n", err

    assert_equal 'darkfish', @options.template
    assert_match %r%rdoc/generator/template/darkfish$%, @options.template_dir
  end

  def test_parse_template_load_path
    orig_LOAD_PATH = $LOAD_PATH.dup

    template_dir = nil

    Dir.mktmpdir do |dir|
      $LOAD_PATH << dir

      template_dir = File.join dir, 'rdoc', 'generator', 'template', 'load_path'

      FileUtils.mkdir_p template_dir

      out, err = capture_output do
        @options.parse %w[--template load_path]
      end

      assert_empty out
      assert_empty err
    end

    assert_equal 'load_path',  @options.template
    assert_equal template_dir, @options.template_dir
  ensure
    $LOAD_PATH.replace orig_LOAD_PATH
  end

  def test_parse_visibility
    @options.parse %w[--visibility=public]
    assert_equal :public, @options.visibility

    @options.parse %w[--visibility=protected]
    assert_equal :protected, @options.visibility

    @options.parse %w[--visibility=private]
    assert_equal :private, @options.visibility

    @options.parse %w[--visibility=nodoc]
    assert_equal :nodoc, @options.visibility
  end

  def test_parse_write_options
    tmpdir = File.join Dir.tmpdir, "test_rdoc_options_#{$$}"
    FileUtils.mkdir_p tmpdir

    Dir.chdir tmpdir do
      e = assert_raise SystemExit do
        @options.parse %w[--write-options]
      end

      assert_equal 0, e.status

      assert File.exist? '.rdoc_options'
    end
  ensure
    FileUtils.rm_rf tmpdir
  end

  def test_parse_extension_alias
    out, err = capture_output do
      @options.parse %w[--extension foobar=rdoc]
    end

    assert_includes RDoc::Parser.parsers, [/\.foobar$/, RDoc::Parser::Simple]

    assert_empty out
    assert_empty err
  end

  def test_setup_generator
    test_generator = Class.new do
      def self.setup_options op
        @op = op
      end

      def self.op() @op end
    end

    RDoc::RDoc::GENERATORS['test'] = test_generator

    @options.setup_generator 'test'

    assert_equal test_generator, @options.generator
    assert_equal [test_generator], @options.generator_options

    assert_equal @options, test_generator.op
  ensure
    RDoc::RDoc::GENERATORS.delete 'test'
  end

  def test_setup_generator_no_option_parser
    test_generator = Class.new do
      def self.setup_options op
        op.option_parser.separator nil
        @op = op
      end

      def self.op() @op end
    end

    RDoc::RDoc::GENERATORS['test'] = test_generator

    @options.setup_generator 'test'

    assert_equal test_generator, @options.generator
    assert_equal [test_generator], @options.generator_options

    assert_equal @options, test_generator.op
  ensure
    RDoc::RDoc::GENERATORS.delete 'test'
  end

  def test_update_output_dir
    assert @options.update_output_dir

    @options.update_output_dir = false

    refute @options.update_output_dir
  end

  def test_warn
    out, err = capture_output do
      @options.warn "warnings off"
    end

    assert_empty out
    assert_empty err

    @options.verbosity = 2

    out, err = verbose_capture_output do
      @options.warn "warnings on"
    end

    assert_empty out
    assert_equal "warnings on\n", err
  end

  def test_write_options
    temp_dir do |dir|
      @options.write_options

      assert File.exist? '.rdoc_options'

      assert_equal @options, YAML.load(File.read('.rdoc_options'))
    end
  end

  def test_version
    out, _ = capture_output do
      begin
        @options.parse %w[--version]
      rescue SystemExit
      end
    end

    assert out.include?(RDoc::VERSION)

    out, _ = capture_output do
      begin
        @options.parse %w[-v]
      rescue SystemExit
      end
    end

    assert out.include?(RDoc::VERSION)
  end

  def test_visibility
    @options.visibility = :all
    assert_equal :private, @options.visibility
  end
end
