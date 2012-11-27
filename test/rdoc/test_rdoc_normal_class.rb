require File.expand_path '../xref_test_case', __FILE__

class TestRDocNormalClass < XrefTestCase

  def test_ancestors
    klass = @top_level.add_class RDoc::NormalClass, 'Klass'
    incl = RDoc::Include.new 'Incl', ''

    sub_klass = @top_level.add_class RDoc::NormalClass, 'SubClass'
    sub_klass.superclass = klass
    sub_klass.add_include incl

    assert_equal [incl.name, klass, 'Object'], sub_klass.ancestors
  end

  def test_ancestors_multilevel
    c1 = @top_level.add_class RDoc::NormalClass, 'Outer'
    c2 = @top_level.add_class RDoc::NormalClass, 'Middle', c1
    c3 = @top_level.add_class RDoc::NormalClass, 'Inner', c2

    assert_equal [c2, c1, 'Object'], c3.ancestors
  end

  def test_direct_ancestors
    incl = RDoc::Include.new 'Incl', ''

    c1 = @top_level.add_class RDoc::NormalClass, 'Outer'
    c2 = @top_level.add_class RDoc::NormalClass, 'Middle', c1
    c3 = @top_level.add_class RDoc::NormalClass, 'Inner', c2
    c3.add_include incl

    assert_equal [incl.name, c2], c3.direct_ancestors
  end

  def test_definition
    c = RDoc::NormalClass.new 'C'

    assert_equal 'class C', c.definition
  end

end

