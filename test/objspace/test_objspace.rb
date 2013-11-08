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
    assert_not_empty(arg)
    bug8014 = '[ruby-core:53130] [Bug #8014]'
    assert_empty(arg.select {|k, v| !(Symbol === k && Integer === v)}, bug8014)
  end

  def test_count_tdata_objects
    res = ObjectSpace.count_tdata_objects
    assert_equal(false, res.empty?)
    arg = {}
    ObjectSpace.count_tdata_objects(arg)
    assert_equal(false, arg.empty?)
  end

  def test_reachable_objects_from
    assert_separately %w[--disable-gem -robjspace], __FILE__, __LINE__, <<-'eom'
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
    assert_operator(max, :>=, long_ary.size+1, "1000 elems + Array class")
    eom
  end

  def test_reachable_objects_from_root
    root_objects = ObjectSpace.reachable_objects_from_root

    assert_operator(root_objects.size, :>, 0)

    root_objects.each{|category, objects|
      assert_kind_of(String, category)
      assert_kind_of(Array, objects)
      assert_operator(objects.size, :>, 0)
    }
  end

  def test_reachable_objects_size
    assert_separately %w[--disable-gem -robjspace], __FILE__, __LINE__, <<-'eom'
    ObjectSpace.each_object{|o|
      ObjectSpace.reachable_objects_from(o).each{|reached_obj|
        size = ObjectSpace.memsize_of(reached_obj)
        assert_kind_of(Integer, size)
        assert_operator(size, :>=, 0)
      }
    }
    eom
  end

  def test_trace_object_allocations
    o0 = Object.new
    ObjectSpace.trace_object_allocations{
      o1 = Object.new; line1 = __LINE__; c1 = GC.count
      o2 = "xyzzy"   ; line2 = __LINE__; c2 = GC.count
      o3 = [1, 2]    ; line3 = __LINE__; c3 = GC.count

      assert_equal(nil, ObjectSpace.allocation_sourcefile(o0))
      assert_equal(nil, ObjectSpace.allocation_sourceline(o0))
      assert_equal(nil, ObjectSpace.allocation_generation(o0))

      assert_equal(line1,    ObjectSpace.allocation_sourceline(o1))
      assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(o1))
      assert_equal(c1,       ObjectSpace.allocation_generation(o1))
      assert_equal(Class.name, ObjectSpace.allocation_class_path(o1))
      assert_equal(:new,       ObjectSpace.allocation_method_id(o1))

      assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(o2))
      assert_equal(line2,    ObjectSpace.allocation_sourceline(o2))
      assert_equal(c2,       ObjectSpace.allocation_generation(o2))
      assert_equal(self.class.name, ObjectSpace.allocation_class_path(o2))
      assert_equal(__method__,      ObjectSpace.allocation_method_id(o2))

      assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(o3))
      assert_equal(line3,    ObjectSpace.allocation_sourceline(o3))
      assert_equal(c3,       ObjectSpace.allocation_generation(o3))
      assert_equal(self.class.name, ObjectSpace.allocation_class_path(o3))
      assert_equal(__method__,      ObjectSpace.allocation_method_id(o3))
    }
  end

  def test_trace_object_allocations_start_stop_clear
    begin
      ObjectSpace.trace_object_allocations_start
      begin
        ObjectSpace.trace_object_allocations_start
        begin
          ObjectSpace.trace_object_allocations_start
          obj0 = Object.new
        ensure
          ObjectSpace.trace_object_allocations_stop
          obj1 = Object.new
        end
      ensure
        ObjectSpace.trace_object_allocations_stop
        obj2 = Object.new
      end
    ensure
      ObjectSpace.trace_object_allocations_stop
      obj3 = Object.new
    end

    assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(obj0))
    assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(obj1))
    assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(obj2))
    assert_equal(nil     , ObjectSpace.allocation_sourcefile(obj3)) # after tracing

    ObjectSpace.trace_object_allocations_clear
    assert_equal(nil, ObjectSpace.allocation_sourcefile(obj0))
    assert_equal(nil, ObjectSpace.allocation_sourcefile(obj1))
    assert_equal(nil, ObjectSpace.allocation_sourcefile(obj2))
    assert_equal(nil, ObjectSpace.allocation_sourcefile(obj3))
  end

  def test_after_gc_start_hook_with_GC_stress
    bug8492 = '[ruby-dev:47400] [Bug #8492]: infinite after_gc_start_hook reentrance'
    assert_nothing_raised(Timeout::Error, bug8492) do
      assert_in_out_err(%w[-robjspace], <<-'end;', /\A[1-9]/, timeout: 2)
        stress, GC.stress = GC.stress, false
        count = 0
        ObjectSpace.after_gc_start_hook = proc {count += 1}
        begin
          GC.stress = true
          3.times {Object.new}
        ensure
          GC.stress = stress
          ObjectSpace.after_gc_start_hook = nil
        end
        puts count
      end;
    end
  end

  def test_dump
    info = nil
    ObjectSpace.trace_object_allocations do
      str = "hello world"
      info = ObjectSpace.dump(str)
    end

    assert_match /"type":"STRING"/, info
    assert_match /"embedded":true, "bytesize":11, "value":"hello world", "encoding":"UTF-8"/, info
    assert_match /"file":"#{Regexp.escape __FILE__}", "line":#{__LINE__-6}/, info
    assert_match /"method":"test_dump"/, info
  end

  def test_dump_all
    entry = /"value":"this is a test string", "encoding":"UTF-8", "file":"-", "line":4, "method":"dump_my_heap_please"/
    assert_in_out_err(%w[-robjspace], <<-'end;', entry)
      def dump_my_heap_please
        ObjectSpace.trace_object_allocations_start
        GC.start
        "this is a test string".force_encoding("UTF-8")
        ObjectSpace.dump_all(output: :stdout)
      end

      dump_my_heap_please
    end;
  end
end
