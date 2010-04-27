require 'tempfile'
require 'rubygems'
require 'minitest/autorun'
require 'rdoc/markup/preprocess'
require 'rdoc/code_objects'

class TestRDocMarkupPreProcess < MiniTest::Unit::TestCase

  def setup
    RDoc::Markup::PreProcess.registered.clear

    @tempfile = Tempfile.new 'test_rdoc_markup_pre_process'
    @name = File.basename @tempfile.path
    @dir  = File.dirname @tempfile.path

    @pp = RDoc::Markup::PreProcess.new __FILE__, [@dir]
  end

  def teardown
    @tempfile.close
  end

  def test_include_file
    @tempfile.write <<-INCLUDE
# -*- mode: rdoc; coding: utf-8; fill-column: 74; -*-

Regular expressions (<i>regexp</i>s) are patterns which describe the
contents of a string.
    INCLUDE

    @tempfile.flush
    @tempfile.rewind

    content = @pp.include_file @name, ''

    expected = <<-EXPECTED
Regular expressions (<i>regexp</i>s) are patterns which describe the
contents of a string.
    EXPECTED

    assert_equal expected, content
  end

  def test_handle
    text = "# :x: y\n"
    out = @pp.handle text

    assert_same out, text
    assert_equal "# :x: y\n", text
  end

  def test_handle_block
    text = "# :x: y\n"

    @pp.handle text do |directive, param|
      false
    end

    assert_equal "# :x: y\n", text

    @pp.handle text do |directive, param|
      ''
    end

    assert_equal "", text
  end

  def test_handle_code_object
    cd = RDoc::CodeObject.new
    text = "# :x: y\n"
    @pp.handle text, cd

    assert_equal "# :x: y\n", text
    assert_equal 'y', cd.metadata['x']

    cd.metadata.clear
    text = "# :x:\n"
    @pp.handle text, cd

    assert_equal "# :x: \n", text
    assert_includes cd.metadata, 'x'
  end

  def test_handle_code_object_block
    cd = RDoc::CodeObject.new
    text = "# :x: y\n"
    @pp.handle text, cd do
      false
    end

    assert_equal "# :x: y\n", text
    assert_empty cd.metadata

    @pp.handle text, cd do
      nil
    end

    assert_equal "# :x: y\n", text
    assert_equal 'y', cd.metadata['x']

    cd.metadata.clear

    @pp.handle text, cd do
      ''
    end

    assert_equal '', text
    assert_empty cd.metadata
  end

  def test_handle_registered
    RDoc::Markup::PreProcess.register 'x'
    text = "# :x: y\n"
    @pp.handle text

    assert_equal '', text

    text = "# :x: y\n"

    @pp.handle text do |directive, param|
      false
    end

    assert_equal "# :x: y\n", text

    text = "# :x: y\n"

    @pp.handle text do |directive, param|
      ''
    end

    assert_equal "", text
  end

  def test_handle_registered_block
    called = nil
    RDoc::Markup::PreProcess.register 'x' do |directive, param|
      called = [directive, param]
      'blah'
    end

    text = "# :x: y\n"
    @pp.handle text

    assert_equal 'blah', text
    assert_equal %w[x y], called
  end

  def test_handle_registered_code_object
    RDoc::Markup::PreProcess.register 'x'
    cd = RDoc::CodeObject.new

    text = "# :x: y\n"
    @pp.handle text, cd

    assert_equal '', text
    assert_equal 'y', cd.metadata['x']

    cd.metadata.clear
    text = "# :x: y\n"

    @pp.handle text do |directive, param|
      false
    end

    assert_equal "# :x: y\n", text
    assert_empty cd.metadata

    text = "# :x: y\n"

    @pp.handle text do |directive, param|
      ''
    end

    assert_equal "", text
    assert_empty cd.metadata
  end

end

