require 'rubygems'
require 'minitest/autorun'
require File.expand_path '../xref_test_case', __FILE__

class TestRDocTopLevel < XrefTestCase

  def setup
    super

    @top_level = RDoc::TopLevel.new 'path/top_level.rb'
  end

  def test_class_all_classes_and_modules
    expected = %w[
      C1 C2 C2::C3 C2::C3::H1 C3 C3::H1 C3::H2 C4 C4::C4 C5 C5::C1
      Child
      M1 M1::M2
      Parent
    ]

    assert_equal expected,
                 RDoc::TopLevel.all_classes_and_modules.map { |m| m.full_name }.sort
  end

  def test_class_classes
    expected = %w[
      C1 C2 C2::C3 C2::C3::H1 C3 C3::H1 C3::H2 C4 C4::C4 C5 C5::C1
      Child Parent
    ]

    assert_equal expected, RDoc::TopLevel.classes.map { |m| m.full_name }.sort
  end

  def test_class_complete
    @c2.add_module_alias @c2_c3, 'A1', @top_level

    RDoc::TopLevel.complete :public

    a1 = @xref_data.find_class_or_module 'C2::A1'

    assert_equal 'C2::A1', a1.full_name
    refute_empty a1.aliases
  end

  def test_class_files
    assert_equal %w[path/top_level.rb xref_data.rb],
                 RDoc::TopLevel.files.map { |m| m.full_name }.sort
  end

  def test_class_find_class_named
    assert_equal @c1, RDoc::TopLevel.find_class_named('C1')

    assert_equal @c2_c3, RDoc::TopLevel.find_class_named('C2::C3')
  end

  def test_class_find_class_named_from
    assert_equal @c5_c1, RDoc::TopLevel.find_class_named_from('C1', 'C5')

    assert_equal @c1,    RDoc::TopLevel.find_class_named_from('C1', 'C4')
  end

  def test_class_find_class_or_module
    assert_equal @m1, RDoc::TopLevel.find_class_or_module('M1')
    assert_equal @c1, RDoc::TopLevel.find_class_or_module('C1')

    assert_equal @m1, RDoc::TopLevel.find_class_or_module('::M1')
    assert_equal @c1, RDoc::TopLevel.find_class_or_module('::C1')
  end

  def test_class_find_file_named
    assert_equal @xref_data, RDoc::TopLevel.find_file_named(@file_name)
  end

  def test_class_find_module_named
    assert_equal @m1,    RDoc::TopLevel.find_module_named('M1')
    assert_equal @m1_m2, RDoc::TopLevel.find_module_named('M1::M2')
  end

  def test_class_modules
    assert_equal %w[M1 M1::M2],
                 RDoc::TopLevel.modules.map { |m| m.full_name }.sort
  end

  def test_class_reset
    RDoc::TopLevel.reset

    assert_empty RDoc::TopLevel.classes
    assert_empty RDoc::TopLevel.modules
    assert_empty RDoc::TopLevel.files
  end

  def test_base_name
    assert_equal 'top_level.rb', @top_level.base_name
  end

  def test_find_class_or_module
    assert_equal @c1,    @xref_data.find_class_or_module('C1')
    assert_equal @c2_c3, @xref_data.find_class_or_module('C2::C3')
    assert_equal @c4,    @xref_data.find_class_or_module('C4')
    assert_equal @m1_m2, @xref_data.find_class_or_module('M1::M2')
  end

  def test_full_name
    assert_equal 'path/top_level.rb', @top_level.full_name
  end

  def test_http_url
    assert_equal 'prefix/path/top_level_rb.html', @top_level.http_url('prefix')
  end

  def test_last_modified
    assert_equal nil, @top_level.last_modified
    stat = Object.new
    def stat.mtime() 0 end
    @top_level.file_stat = stat
    assert_equal 0, @top_level.last_modified
  end

  def test_name
    assert_equal 'top_level.rb', @top_level.name
  end

end

