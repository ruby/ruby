require "test/unit"
require "objspace"

class TestObjSpace < Test::Unit::TestCase
  def test_memsize_of
    assert_equal(0, ObjectSpace.memsize_of(true))
    assert_equal(0, ObjectSpace.memsize_of(nil))
    assert_equal(0, ObjectSpace.memsize_of(1))
    assert_kind_of(Integer, ObjectSpace.memsize_of(Object.new))
    assert_kind_of(Integer, ObjectSpace.memsize_of(Class))
    assert_kind_of(Integer, ObjectSpace.memsize_of(""))
    assert_kind_of(Integer, ObjectSpace.memsize_of([]))
    assert_kind_of(Integer, ObjectSpace.memsize_of({}))
    assert_kind_of(Integer, ObjectSpace.memsize_of(//))
    f = File.new(__FILE__)
    assert_kind_of(Integer, ObjectSpace.memsize_of(f))
    f.close
    assert_kind_of(Integer, ObjectSpace.memsize_of(/a/.match("a")))
    assert_kind_of(Integer, ObjectSpace.memsize_of(Struct.new(:a)))
  end

  def test_total_memsize_of_all_objects
    assert_kind_of(Integer, ObjectSpace.total_memsize_of_all_objects)
  end

  def test_count_objects_size
    res = ObjectSpace.count_objects_size
    assert_equal(false, res.empty?)
    assert_equal(true, res[:TOTAL] > 0)
    arg = {}
    ObjectSpace.count_objects_size(arg)
    assert_equal(false, arg.empty?)
  end

  def test_count_nodes
    res = ObjectSpace.count_nodes
    assert_equal(false, res.empty?)
    arg = {}
    ObjectSpace.count_nodes(arg)
    assert_equal(false, arg.empty?)
  end

  def test_count_tdata_objects
    res = ObjectSpace.count_tdata_objects
    assert_equal(false, res.empty?)
    arg = {}
    ObjectSpace.count_tdata_objects(arg)
    assert_equal(false, arg.empty?)
  end
end
