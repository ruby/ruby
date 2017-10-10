# frozen_string_literal: false
require "test/unit"
require "objspace"
begin
  require "json"
rescue LoadError
end

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
    rv_size = GC::INTERNAL_CONSTANTS[:RVALUE_SIZE]
    assert_equal([rv_size, rv_size, 26 + rv_size], [a, b, c].map {|x| ObjectSpace.memsize_of(x)})
  end

  def test_argf_memsize
    size = ObjectSpace.memsize_of(ARGF)
    assert_kind_of(Integer, size)
    assert_operator(size, :>, 0)
    argf = ARGF.dup
    argf.inplace_mode = nil
    size = ObjectSpace.memsize_of(argf)
    argf.inplace_mode = "inplace_mode_suffix"
    assert_equal(size, ObjectSpace.memsize_of(argf))
  end

  def test_memsize_of_all
    assert_kind_of(Integer, a = ObjectSpace.memsize_of_all)
    assert_kind_of(Integer, b = ObjectSpace.memsize_of_all(String))
    assert_operator(a, :>, b)
    assert_operator(a, :>, 0)
    assert_operator(b, :>, 0)
    assert_raise(TypeError) {ObjectSpace.memsize_of_all('error')}
  end

  def test_count_objects_size
    res = ObjectSpace.count_objects_size
    assert_not_empty(res)
    assert_operator(res[:TOTAL], :>, 0)
  end

  def test_count_objects_size_with_hash
    arg = {}
    ObjectSpace.count_objects_size(arg)
    assert_not_empty(arg)
    arg = {:TOTAL => 1 }
    ObjectSpace.count_objects_size(arg)
    assert_not_empty(arg)
  end

  def test_count_objects_size_with_wrong_type
    assert_raise(TypeError) { ObjectSpace.count_objects_size(0) }
  end

  def test_count_nodes
    res = ObjectSpace.count_nodes
    assert_not_empty(res)
    arg = {}
    ObjectSpace.count_nodes(arg)
    assert_not_empty(arg)
    bug8014 = '[ruby-core:53130] [Bug #8014]'
    assert_empty(arg.select {|k, v| !(Symbol === k && Integer === v)}, bug8014)
  end if false

  def test_count_tdata_objects
    res = ObjectSpace.count_tdata_objects
    assert_not_empty(res)
    arg = {}
    ObjectSpace.count_tdata_objects(arg)
    assert_not_empty(arg)
  end

  def test_count_imemo_objects
    res = ObjectSpace.count_imemo_objects
    assert_not_empty(res)
    assert_not_nil(res[:imemo_cref])
    arg = {}
    res = ObjectSpace.count_imemo_objects(arg)
    assert_not_empty(res)
  end

  def test_memsize_of_iseq
    iseqw = RubyVM::InstructionSequence.compile('def a; a = :b; end')
    base_obj_size = ObjectSpace.memsize_of(Object.new)
    assert_operator(ObjectSpace.memsize_of(iseqw), :>, base_obj_size)
  end

  def test_reachable_objects_from
    assert_separately %w[--disable-gem -robjspace], "#{<<-"begin;"}\n#{<<-'end;'}"
    begin;
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
    end;
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
    assert_separately %w[--disable-gem -robjspace], "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      ObjectSpace.each_object{|o|
        ObjectSpace.reachable_objects_from(o).each{|reached_obj|
          size = ObjectSpace.memsize_of(reached_obj)
          assert_kind_of(Integer, size)
          assert_operator(size, :>=, 0)
        }
      }
    end;
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
    ObjectSpace.trace_object_allocations_clear # clear object_table to get rid of erroneous detection for obj3
    GC.disable # suppress potential object reuse. see [Bug #11271]
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
  ensure
    GC.enable
  end

  def test_dump_flags
    info = ObjectSpace.dump("foo".freeze)
    assert_match /"wb_protected":true, "old":true/, info
    assert_match /"fstring":true/, info
    JSON.parse(info) if defined?(JSON)
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
    JSON.parse(info) if defined?(JSON)
  end

  def test_dump_special_consts
    # [ruby-core:69692] [Bug #11291]
    assert_equal('null', ObjectSpace.dump(nil))
    assert_equal('true', ObjectSpace.dump(true))
    assert_equal('false', ObjectSpace.dump(false))
    assert_equal('0', ObjectSpace.dump(0))
    assert_equal('{"type":"SYMBOL", "value":"foo"}', ObjectSpace.dump(:foo))
  end

  def test_dump_dynamic_symbol
    dump = ObjectSpace.dump(("foobar%x" % rand(0x10000)).to_sym)
    assert_match /"type":"SYMBOL"/, dump
    assert_match /"value":"foobar\h+"/, dump
  end

  def test_dump_includes_imemo_type
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          ObjectSpace.dump_all(output: :stdout)
        end

        dump_my_heap_please
      end;
      heap = output.find_all { |l|
        obj = JSON.parse(l)
        obj['type'] == "IMEMO" && obj['imemo_type']
      }
      assert_operator heap.length, :>, 0
    end
  end

  def test_dump_all_full
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          ObjectSpace.dump_all(output: :stdout, full: true)
        end

        dump_my_heap_please
      end;
      heap = output.find_all { |l| JSON.parse(l)['type'] == "NONE" }
      assert_operator heap.length, :>, 0
    end
  end

  def test_dump_all
    entry = /"bytesize":11, "value":"TEST STRING", "encoding":"UTF-8", "file":"-", "line":4, "method":"dump_my_heap_please", "generation":/

    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}#{<<-'end;'}") do |output, error|
      begin;
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

    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}#{<<-'end;'}") do |(output), (error)|
      begin;
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

    if defined?(JSON)
      args = [
        "-rjson", "-",
        EnvUtil.rubybin,
        "--disable=gems", "-robjspace", "-eObjectSpace.dump_all(output: :stdout)",
      ]
      assert_ruby_status(args, "#{<<~"begin;"}\n#{<<~"end;"}")
      begin;
        IO.popen(ARGV) do |f|
          f.each_line.map { |x| JSON.load(x) }
        end
      end;
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

  def traverse_classes klass
    h = {}
    while klass && !h.has_key?(klass)
      h[klass] = true
      klass = ObjectSpace.internal_class_of(klass)
    end
  end

  def test_internal_class_of
    i = 0
    ObjectSpace.each_object{|o|
      traverse_classes ObjectSpace.internal_class_of(o)
      i += 1
    }
    assert_operator i, :>, 0
  end

  def traverse_super_classes klass
    while klass
      klass = ObjectSpace.internal_super_of(klass)
    end
  end

  def all_super_classes klass
    klasses = []
    while klass
      klasses << klass
      klass = ObjectSpace.internal_super_of(klass)
    end
    klasses
  end

  def test_internal_super_of
    klasses = all_super_classes(String)
    String.ancestors.each{|k|
      case k
      when Class
        assert_equal(true, klasses.include?(k), k.inspect)
      when Module
        assert_equal(false, klasses.include?(k), k.inspect) # Internal object (T_ICLASS)
      end
    }

    i = 0
    ObjectSpace.each_object(Module){|o|
      traverse_super_classes ObjectSpace.internal_super_of(o)
      i += 1
    }
    assert_operator i, :>, 0
  end

  def test_count_symbols
    assert_separately(%w[-robjspace], "#{<<~';;;'}")
    h0 = ObjectSpace.count_symbols

    syms = (1..128).map{|i| ("xyzzy#{i}_#{Process.pid}_#{rand(1_000_000)}_" * 128).to_sym}
    syms << Class.new{define_method(syms[-1]){}}

    h = ObjectSpace.count_symbols
    m = proc {h0.inspect + "\n" + h.inspect}
    assert_equal 127, h[:mortal_dynamic_symbol] - h0[:mortal_dynamic_symbol],   m
    assert_equal 1, h[:immortal_dynamic_symbol] - h0[:immortal_dynamic_symbol], m
    assert_operator h[:immortal_static_symbol],  :>=, Object.methods.size, m
    assert_equal h[:immortal_symbol], h[:immortal_dynamic_symbol] + h[:immortal_static_symbol], m
    ;;;
  end
end
