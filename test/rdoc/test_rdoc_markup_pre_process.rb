require 'tempfile'
require 'rubygems'
require 'minitest/autorun'
require 'rdoc/markup/preprocess'

class TestRDocMarkupPreProcess < MiniTest::Unit::TestCase

  def setup
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

end

