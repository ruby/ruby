# frozen_string_literal: true
require_relative 'helper'

class RDocGeneratorRITest < RDoc::TestCase

  def setup
    super

    @options = RDoc::Options.new
    @options.encoding = Encoding::UTF_8
    @store.encoding = Encoding::UTF_8

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_generator_ri_#{$$}"
    FileUtils.mkdir_p @tmpdir

    @g = RDoc::Generator::RI.new @store, @options

    @top_level = @store.add_file 'file.rb'
    @klass = @top_level.add_class RDoc::NormalClass, 'Object'

    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth.record_location @top_level

    @meth_bang = RDoc::AnyMethod.new nil, 'method!'
    @meth_bang.record_location @top_level

    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''
    @attr.record_location @top_level

    @klass.add_method @meth
    @klass.add_method @meth_bang
    @klass.add_attribute @attr

    Dir.chdir @tmpdir
  end

  def teardown
    super

    Dir.chdir @pwd
    FileUtils.rm_rf @tmpdir
  end

  def test_generate
    @g.generate

    assert_file File.join(@tmpdir, 'cache.ri')

    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_file File.join(@tmpdir, 'Object', 'attr-i.ri')
    assert_file File.join(@tmpdir, 'Object', 'method-i.ri')
    assert_file File.join(@tmpdir, 'Object', 'method%21-i.ri')

    store = RDoc::RI::Store.new(@options, path: @tmpdir)
    store.load_cache

    encoding = Encoding::UTF_8

    assert_equal encoding, store.encoding
  end

  def test_generate_dry_run
    @store.dry_run = true
    @g = RDoc::Generator::RI.new @store, @options

    top_level = @store.add_file 'file.rb'
    top_level.add_class @klass.class, @klass.name

    @g.generate

    refute_file File.join(@tmpdir, 'cache.ri')
    refute_file File.join(@tmpdir, 'Object')
  end

end
