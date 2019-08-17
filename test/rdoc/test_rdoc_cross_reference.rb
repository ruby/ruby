# frozen_string_literal: true
require File.expand_path '../xref_test_case', __FILE__

class TestRDocCrossReference < XrefTestCase

  def setup
    super

    @xref = RDoc::CrossReference.new @c1
  end

  def assert_ref expected, name
    assert_equal expected, @xref.resolve(name, 'fail')
  end

  def refute_ref name
    assert_equal name, @xref.resolve(name, name)
  end

  def test_METHOD_REGEXP_STR
    re = /#{RDoc::CrossReference::METHOD_REGEXP_STR}/

    %w'=== [] []= << >>'.each do |x|
      re =~ x
      assert_equal x, $&
    end
  end

  def test_resolve_C2
    @xref = RDoc::CrossReference.new @c2

    refute_ref '#m'

    assert_ref @c1__m,    'C1::m'
    assert_ref @c2_c3,    'C2::C3'
    assert_ref @c2_c3_m,  'C2::C3#m'
    assert_ref @c2_c3_h1, 'C3::H1'
    assert_ref @c4,       'C4'

    assert_ref @c3_h2, 'C3::H2'
    refute_ref 'H1'
  end

  def test_resolve_C2_C3
    @xref = RDoc::CrossReference.new @c2_c3

    assert_ref @c2_c3_m, '#m'

    assert_ref @c2_c3, 'C3'
    assert_ref @c2_c3_m, 'C3#m'

    assert_ref @c2_c3_h1, 'H1'
    assert_ref @c2_c3_h1, 'C3::H1'

    assert_ref @c4, 'C4'

    assert_ref @c3_h2, 'C3::H2'
  end

  def test_resolve_C3
    @xref = RDoc::CrossReference.new @c3

    assert_ref @c3, 'C3'

    refute_ref '#m'
    refute_ref 'C3#m'

    assert_ref @c3_h1, 'H1'

    assert_ref @c3_h1, 'C3::H1'
    assert_ref @c3_h2, 'C3::H2'

    assert_ref @c4, 'C4'
  end

  def test_resolve_C4
    @xref = RDoc::CrossReference.new @c4

    # C4 ref inside a C4 containing a C4 should resolve to the contained class
    assert_ref @c4_c4, 'C4'
  end

  def test_resolve_C4_C4
    @xref = RDoc::CrossReference.new @c4_c4

    # A C4 reference inside a C4 class contained within a C4 class should
    # resolve to the inner C4 class.
    assert_ref @c4_c4, 'C4'
  end

  def test_resolve_class
    assert_ref @c1, 'C1'
    refute_ref 'H1'

    assert_ref @c2,       'C2'
    assert_ref @c2_c3,    'C2::C3'
    assert_ref @c2_c3_h1, 'C2::C3::H1'

    assert_ref @c3,    '::C3'
    assert_ref @c3_h1, '::C3::H1'

    assert_ref @c4_c4, 'C4::C4'
  end

  def test_resolve_file
    refute_ref 'xref_data.rb'
  end

  def test_resolve_method
    assert_ref @c1__m,    'm'
    assert_ref @c1__m,    '::m'
    assert_ref @c1_m,     '#m'
    assert_ref @c1_plus,  '#+'

    assert_ref @c1_m,     'C1#m'
    assert_ref @c1_plus,  'C1#+'
    assert_ref @c1__m,    'C1.m'
    assert_ref @c1__m,    'C1::m'

    assert_ref @c1_m, 'C1#m'
    assert_ref @c1_m, 'C1#m()'
    assert_ref @c1_m, 'C1#m(*)'

    assert_ref @c1_plus, 'C1#+'
    assert_ref @c1_plus, 'C1#+()'
    assert_ref @c1_plus, 'C1#+(*)'

    assert_ref @c1__m, 'C1.m'
    assert_ref @c1__m, 'C1.m()'
    assert_ref @c1__m, 'C1.m(*)'

    assert_ref @c1__m, 'C1::m'
    assert_ref @c1__m, 'C1::m()'
    assert_ref @c1__m, 'C1::m(*)'

    assert_ref @c2_c3_m, 'C2::C3#m'

    assert_ref @c2_c3_m, 'C2::C3.m'

    # TODO stop escaping - HTML5 allows anything but space
    assert_ref @c2_c3_h1_meh, 'C2::C3::H1#m?'

    assert_ref @c2_c3_m, '::C2::C3#m'
    assert_ref @c2_c3_m, '::C2::C3#m()'
    assert_ref @c2_c3_m, '::C2::C3#m(*)'
  end

  def test_resolve_the_same_name_in_instance_and_class_method
    assert_ref @c9_a_i_foo, 'C9::A#foo'
    assert_ref @c9_a_c_bar, 'C9::A::bar'
    assert_ref @c9_b_c_foo, 'C9::B::foo'
    assert_ref @c9_b_i_bar, 'C9::B#bar'
    assert_ref @c9_b_c_foo, 'C9::B.foo'
    assert_ref @c9_a_c_bar, 'C9::B.bar'
  end

  def test_resolve_method_equals3
    m = RDoc::AnyMethod.new '', '==='
    @c1.add_method m

    assert_ref m, '==='
  end

  def test_resolve_page
    page = @store.add_file 'README.txt', parser: RDoc::Parser::Simple

    assert_ref page, 'README'
  end

  def test_resolve_percent
    i_percent = RDoc::AnyMethod.new nil, '%'
    i_percent.singleton = false
    @c1.add_method i_percent

    c_percent = RDoc::AnyMethod.new nil, '%'
    c_percent.singleton = true
    @c1.add_method c_percent

    assert_ref i_percent, '%'
    assert_ref i_percent, '#%'
    assert_ref c_percent, '::%'

    assert_ref i_percent, 'C1#%'
    assert_ref c_percent, 'C1::%'
  end

  def test_resolve_no_ref
    assert_equal '', @xref.resolve('', '')

    assert_equal "bogus",     @xref.resolve("bogus",     "bogus")
    assert_equal "\\bogus",   @xref.resolve("\\bogus",   "\\bogus")
    assert_equal "\\\\bogus", @xref.resolve("\\\\bogus", "\\\\bogus")

    assert_equal "\\#n",    @xref.resolve("\\#n",    "fail")
    assert_equal "\\#n()",  @xref.resolve("\\#n()",  "fail")
    assert_equal "\\#n(*)", @xref.resolve("\\#n(*)", "fail")

    assert_equal "C1",   @xref.resolve("\\C1",   "fail")
    assert_equal "::C3", @xref.resolve("\\::C3", "fail")

    assert_equal "succeed",      @xref.resolve("::C3::H1#n",    "succeed")
    assert_equal "succeed",      @xref.resolve("::C3::H1#n(*)", "succeed")
    assert_equal "\\::C3::H1#n", @xref.resolve("\\::C3::H1#n",  "fail")
  end

end

