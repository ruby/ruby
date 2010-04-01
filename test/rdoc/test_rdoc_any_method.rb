require File.expand_path '../xref_test_case', __FILE__

class RDocAnyMethodTest < XrefTestCase

  def test_full_name
    assert_equal 'C1::m', @c1.method_list.first.full_name
  end

  def test_parent_name
    assert_equal 'C1', @c1.method_list.first.parent_name
    assert_equal 'C1', @c1.method_list.last.parent_name
  end

  def test_marshal_load
    instance_method = Marshal.load Marshal.dump(@c1.method_list.last)

    assert_equal 'C1#m', instance_method.full_name
    assert_equal 'C1',   instance_method.parent_name

    class_method = Marshal.load Marshal.dump(@c1.method_list.first)

    assert_equal 'C1::m', class_method.full_name
    assert_equal 'C1',    class_method.parent_name
  end

  def test_name
    m = RDoc::AnyMethod.new nil, nil

    assert_nil m.name
  end

end

