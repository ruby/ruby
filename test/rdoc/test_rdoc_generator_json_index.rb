# coding: US-ASCII
# frozen_string_literal: true

require 'minitest_helper'

class TestRDocGeneratorJsonIndex < RDoc::TestCase

  def setup
    super

    @tmpdir = Dir.mktmpdir "test_rdoc_generator_darkfish_#{$$}_"
    FileUtils.mkdir_p @tmpdir

    @options = RDoc::Options.new
    @options.files = []
    # JsonIndex is used in conjunction with another generator
    @options.setup_generator 'darkfish'
    @options.template_dir = ''
    @options.op_dir = @tmpdir
    @options.option_parser = OptionParser.new
    @options.finish

    @darkfish = RDoc::Generator::Darkfish.new @store, @options
    @g = RDoc::Generator::JsonIndex.new @darkfish, @options

    @rdoc.options = @options
    @rdoc.generator = @g

    @top_level = @store.add_file 'file.rb'
    @top_level.parser = RDoc::Parser::Ruby

    @klass = @top_level.add_class RDoc::NormalClass, 'C'

    @meth = @klass.add_method RDoc::AnyMethod.new(nil, 'meth')
    @meth.record_location @top_level

    @nest_klass = @klass.add_class RDoc::NormalClass, 'D'
    @nest_klass.record_location @top_level

    @nest_meth = @nest_klass.add_method RDoc::AnyMethod.new(nil, 'meth')

    @ignored = @top_level.add_class RDoc::NormalClass, 'Ignored'
    @ignored.ignore

    @page = @store.add_file 'page.rdoc'
    @page.parser = RDoc::Parser::Simple

    @top_levels = [@top_level, @page].sort
    @klasses    = [@klass, @nest_klass, @ignored]

    Dir.chdir @tmpdir
  end

  def teardown
    super

    Dir.chdir @pwd
    FileUtils.rm_rf @tmpdir
  end

  def test_build_index
    index = @g.build_index

    expected = {
      :index => {
        :searchIndex     => %w[c d meth() meth() page],
        :longSearchIndex => %w[c c::d c#meth() c::d#meth()],
        :info            => [
          @klass.search_record[2..-1],
          @nest_klass.search_record[2..-1],
          @meth.search_record[2..-1],
          @nest_meth.search_record[2..-1],
          @page.search_record[2..-1],
        ],
      },
    }

    expected[:index][:longSearchIndex] << ''

    assert_equal expected, index
  end

  def test_class_dir
    assert_equal @darkfish.class_dir, @g.class_dir
  end

  def test_file_dir
    assert_equal @darkfish.file_dir, @g.file_dir
  end

  def test_generate
    @g.generate

    assert_file 'js/searcher.js'
    assert_file 'js/navigation.js'
    assert_file 'js/search_index.js'

    srcdir = File.expand_path('lib/rdoc', @pwd)
    if !File.directory? srcdir
      # for Ruby core repository
      srcdir = File.expand_path("../../../lib/rdoc", __FILE__)
    end

    orig_file = Pathname(File.join srcdir, 'generator/template/json_index/js/navigation.js')
    generated_file = Pathname(File.join @tmpdir, 'js/navigation.js')

    # This is dirty hack on JRuby for MiniTest 4
    assert orig_file.mtime.inspect == generated_file.mtime.inspect,
      '.js files should be the same timestamp of original'

    json = File.read 'js/search_index.js'

    json =~ /\Avar search_data = /

    assignment = $&
    index = $'

    refute_empty assignment

    index = JSON.parse index

    info = [
      @klass.search_record[2..-1],
      @nest_klass.search_record[2..-1],
      @meth.search_record[2..-1],
      @nest_meth.search_record[2..-1],
      @page.search_record[2..-1],
    ]

    expected = {
      'index' => {
        'searchIndex' => [
          'c',
          'd',
          'meth()',
          'meth()',
          'page',
        ],
        'longSearchIndex' => [
          'c',
          'c::d',
          'c#meth()',
          'c::d#meth()',
          '',
        ],
        'info' => info,
      },
    }

    assert_equal expected, index
  end

  def test_generate_search_index_with_reproducible_builds
    backup_epoch = ENV['SOURCE_DATE_EPOCH']
    ruby_birthday = Time.parse 'Wed, 24 Feb 1993 21:00:00 +0900'
    ENV['SOURCE_DATE_EPOCH'] = ruby_birthday.to_i.to_s

    @g.generate

    assert_file 'js/search_index.js'
    generated_search_index = Pathname(File.join @tmpdir, 'js/search_index.js')
    assert_equal ruby_birthday, generated_search_index.mtime

    ENV['SOURCE_DATE_EPOCH'] = backup_epoch
  end

  def test_generate_gzipped
    begin
      require 'zlib'
    rescue LoadError
      skip "no zlib"
    end
    @g.generate
    @g.generate_gzipped

    assert_file 'js/searcher.js'
    assert_file 'js/searcher.js.gz'
    assert_file 'js/navigation.js'
    assert_file 'js/navigation.js.gz'
    assert_file 'js/search_index.js'
    assert_file 'js/search_index.js.gz'

    json = File.open('js/search_index.js.gz', 'rb') {|gzip|
      Zlib::GzipReader.new(gzip).read
    }

    json =~ /\Avar search_data = /

    assignment = $&
    index = $'

    refute_empty assignment

    index = JSON.parse index

    info = [
      @klass.search_record[2..-1],
      @nest_klass.search_record[2..-1],
      @meth.search_record[2..-1],
      @nest_meth.search_record[2..-1],
      @page.search_record[2..-1],
    ]

    expected = {
      'index' => {
        'searchIndex' => [
          'c',
          'd',
          'meth()',
          'meth()',
          'page',
        ],
        'longSearchIndex' => [
          'c',
          'c::d',
          'c#meth()',
          'c::d#meth()',
          '',
        ],
        'info' => info,
      },
    }

    assert_equal expected, index
  end

  def test_generate_utf_8
    text = "5\xB0"
    text = RDoc::Encoding.change_encoding text, Encoding::ISO_8859_1
    @klass.add_comment comment(text), @top_level

    @g.generate

    json = File.read 'js/search_index.js'
    json.force_encoding Encoding::UTF_8

    json =~ /\Avar search_data = /

    index = $'

    index = JSON.parse index

    klass_record = @klass.search_record[2..-1]
    klass_record[-1] = "<p>5\xc2\xb0\n"
    klass_record[-1] = RDoc::Encoding.change_encoding klass_record[-1], Encoding::UTF_8

    info = [
      klass_record,
      @nest_klass.search_record[2..-1],
      @meth.search_record[2..-1],
      @nest_meth.search_record[2..-1],
      @page.search_record[2..-1],
    ]

    expected = {
      'index' => {
        'searchIndex' => [
          'c',
          'd',
          'meth()',
          'meth()',
          'page',
        ],
        'longSearchIndex' => [
          'c',
          'c::d',
          'c#meth()',
          'c::d#meth()',
          '',
        ],
        'info' => info,
      },
    }

    assert_equal expected, index
  end

  def test_index_classes
    @g.reset @top_levels, @klasses

    @g.index_classes

    expected = {
      :searchIndex     => %w[c d],
      :longSearchIndex => %w[c c::d],
      :info            => [
        @klass.search_record[2..-1],
        @nest_klass.search_record[2..-1],
      ],
    }

    assert_equal expected, @g.index
  end

  def test_index_classes_nodoc
    @klass.document_self      = false
    @nest_klass.document_self = false
    @meth.document_self       = false
    @nest_meth.document_self  = false

    @g.reset @top_levels, @klasses

    @g.index_classes

    expected = {
      :searchIndex     => [],
      :longSearchIndex => [],
      :info            => [],
    }

    assert_equal expected, @g.index
  end

  def test_index_methods
    @g.reset @top_levels, @klasses

    @g.index_methods

    expected = {
      :searchIndex     => %w[meth() meth()],
      :longSearchIndex => %w[c#meth() c::d#meth()],
      :info            => [
        @meth.search_record[2..-1],
        @nest_meth.search_record[2..-1],
      ],
    }

    assert_equal expected, @g.index
  end

  def test_index_pages
    @g.reset @top_levels, @klasses

    @g.index_pages

    expected = {
      :searchIndex     => %w[page],
      :longSearchIndex => [''],
      :info            => [@page.search_record[2..-1]],
    }

    assert_equal expected, @g.index
  end

  def test_search_string
    assert_equal 'cd', @g.search_string('C d')
  end

end
