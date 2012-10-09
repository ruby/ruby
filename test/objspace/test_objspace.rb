require "test/unit"
require "objspace"
require_relative "../ruby/envutil"

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

    assert_operator(ObjectSpace.memsize_of(Regexp.new("(a)"*1000).match("a"*1000)),
                    :>,
                    ObjectSpace.memsize_of(//.match("")))
  end

  def test_argf_memsize
    size = ObjectSpace.memsize_of(ARGF)
    assert_kind_of(Integer, size)
    assert_operator(size, :>, 0)
    argf = ARGF.dup
    argf.inplace_mode = nil
    size = ObjectSpace.memsize_of(argf)
    argf.inplace_mode = "inplace_mode_suffix"
    assert_equal(size + 20, ObjectSpace.memsize_of(argf))
  end

  def test_memsize_of_all
    assert_kind_of(Integer, a = ObjectSpace.memsize_of_all)
    assert_kind_of(Integer, b = ObjectSpace.memsize_of_all(String))
    assert(a > b)
    assert(a > 0)
    assert(b > 0)
    assert_raise(TypeError) {ObjectSpace.memsize_of_all('error')}
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

  def test_reachable_objects_from
    assert_equal(nil, ObjectSpace.reachable_objects_from(nil))
    assert_equal([Array, 'a', 'b', 'c'], ObjectSpace.reachable_objects_from(['a', 'b', 'c']))

    assert_equal([Array, 'a', 'a', 'a'], ObjectSpace.reachable_objects_from(['a', 'a', 'a']))
    assert_equal([Array, 'a', 'a'], ObjectSpace.reachable_objects_from(['a', v = 'a', v]))
    assert_equal([Array, 'a'], ObjectSpace.reachable_objects_from([v = 'a', v, v]))

    long_ary = Array.new(1_000){''}
    max = 0

    ObjectSpace.each_object{|o|
      refs = ObjectSpace.reachable_objects_from(o)
      max = [refs.size, max].max

      unless refs.nil?
        refs.each_with_index {|ro, i|
          assert_not_nil(ro, "#{i}: this referenced object is internal object")
        }
      end
    }
    assert_operator(max, :>=, 1_001, "1000 elems + Array class")
  end
end
