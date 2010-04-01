require 'rubygems'
require 'minitest/autorun'
require 'rdoc/rdoc'
require 'tmpdir'
require 'fileutils'

class TestRDocGeneratorRI < MiniTest::Unit::TestCase

  def setup
    @pwd = Dir.pwd
    RDoc::TopLevel.reset

    @tmpdir = File.join Dir.tmpdir, "test_rdoc_generator_ri_#{$$}"
    FileUtils.mkdir_p @tmpdir
    Dir.chdir @tmpdir
    options = RDoc::Options.new

    @g = RDoc::Generator::RI.new options

    @top_level = RDoc::TopLevel.new 'file.rb'
    @klass = @top_level.add_class RDoc::NormalClass, 'Object'
    @meth = RDoc::AnyMethod.new nil, 'method'
    @meth_bang = RDoc::AnyMethod.new nil, 'method!'
    @attr = RDoc::Attr.new nil, 'attr', 'RW', ''

    @klass.add_method @meth
    @klass.add_method @meth_bang
    @klass.add_attribute @attr
  end

  def teardown
    Dir.chdir @pwd
    FileUtils.rm_rf @tmpdir
  end

  def assert_file path
    assert File.file?(path), "#{path} is not a file"
  end

  def test_generate
    top_level = RDoc::TopLevel.new 'file.rb'
    top_level.add_class @klass.class, @klass.name

    @g.generate nil

    assert_file File.join(@tmpdir, 'cache.ri')

    assert_file File.join(@tmpdir, 'Object', 'cdesc-Object.ri')

    assert_file File.join(@tmpdir, 'Object', 'attr-i.ri')
    assert_file File.join(@tmpdir, 'Object', 'method-i.ri')
    assert_file File.join(@tmpdir, 'Object', 'method%21-i.ri')
  end

end

