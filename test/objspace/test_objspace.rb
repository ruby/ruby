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

  def test_memsize_of_root_shared_string
    a = "hello" * 5
    b = a.dup
    c = nil
    ObjectSpace.each_object(String) {|x| break c = x if x == a and x.frozen?}
    assert_equal([0, 0, 26], [a, b, c].map {|x| ObjectSpace.memsize_of(x)})
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
    Class.name
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

  def test_dump_flags
    info = ObjectSpace.dump("foo".freeze)
    assert_match /"wb_protected":true, "old":true, "marked":true/, info
    assert_match /"fstring":true/, info
  end

  def test_dump_to_default
    line = nil
    info = nil
    ObjectSpace.trace_object_allocations do
      line = __LINE__ + 1
      str = "hello world"
      info = ObjectSpace.dump(str)
    end
    assert_dump_object(info, line)
  end

  def test_dump_to_io
    line = nil
    info = IO.pipe do |r, w|
      th = Thread.start {r.read}
      ObjectSpace.trace_object_allocations do
        line = __LINE__ + 1
        str = "hello world"
        ObjectSpace.dump(str, output: w)
      end
      w.close
      th.value
    end
    assert_dump_object(info, line)
  end

  def assert_dump_object(info, line)
    loc = caller_locations(1, 1)[0]
    assert_match /"type":"STRING"/, info
    assert_match /"embedded":true, "bytesize":11, "value":"hello world", "encoding":"UTF-8"/, info
    assert_match /"file":"#{Regexp.escape __FILE__}", "line":#{line}/, info
    assert_match /"method":"#{loc.base_label}"/, info
  end

  def test_dump_special_consts
    # [ruby-core:69692] [Bug #11291]
    assert_equal('{}', ObjectSpace.dump(nil))
    assert_equal('{}', ObjectSpace.dump(true))
    assert_equal('{}', ObjectSpace.dump(false))
    assert_equal('{}', ObjectSpace.dump(0))
    assert_equal('{}', ObjectSpace.dump(:foo))
  end

  def test_dump_all
    entry = /"bytesize":11, "value":"TEST STRING", "encoding":"UTF-8", "file":"-", "line":4, "method":"dump_my_heap_please", "generation":/

    assert_in_out_err(%w[-robjspace], <<-'end;') do |output, error|
      def dump_my_heap_please
        ObjectSpace.trace_object_allocations_start
        GC.start
        str = "TEST STRING".force_encoding("UTF-8")
        ObjectSpace.dump_all(output: :stdout)
      end

      dump_my_heap_please
    end;
      assert_match(entry, output.grep(/TEST STRING/).join("\n"))
    end

    assert_in_out_err(%w[-robjspace], <<-'end;') do |(output), (error)|
      def dump_my_heap_please
        ObjectSpace.trace_object_allocations_start
        GC.start
        str = "TEST STRING".force_encoding("UTF-8")
        ObjectSpace.dump_all().path
      end

      puts dump_my_heap_please
    end;
      skip if /is not supported/ =~ error
      skip error unless output
      assert_match(entry, File.readlines(output).grep(/TEST STRING/).join("\n"))
      File.unlink(output)
    end
  end

  def test_dump_uninitialized_file
    assert_in_out_err(%[-robjspace], <<-RUBY) do |(output), (error)|
      puts ObjectSpace.dump(File.allocate)
    RUBY
      assert_nil error
      assert_match /"type":"FILE"/, output
      assert_not_match /"fd":/, output
    end
  end
end
