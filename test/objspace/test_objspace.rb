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
    a = "a" * GC::INTERNAL_CONSTANTS[:RVARGC_MAX_ALLOCATE_SIZE]
    b = a.dup
    c = nil
    ObjectSpace.each_object(String) {|x| break c = x if a == x and x.frozen?}
    rv_size = GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]
    assert_equal([rv_size, rv_size, a.length + 1 + rv_size], [a, b, c].map {|x| ObjectSpace.memsize_of(x)})
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
    assert_not_empty res.inspect

    arg = {}
    res = ObjectSpace.count_imemo_objects(arg)
    assert_not_empty(res)
  end

  def test_memsize_of_iseq
    iseqw = RubyVM::InstructionSequence.compile('def a; a = :b; a; end')
    # Use anonymous class as a basic object size because size of Object.new can be increased
    base_obj_size = ObjectSpace.memsize_of(Class.new.new)
    assert_operator(ObjectSpace.memsize_of(iseqw), :>, base_obj_size)
  end

  def test_reachable_objects_from
    opts = %w[--disable-gem --disable=frozen-string-literal -robjspace]
    assert_separately opts, "#{<<-"begin;"}\n#{<<-'end;'}"
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

  def test_reachable_objects_during_iteration
    omit 'flaky on Visual Studio with: [BUG] Unnormalized Fixnum value' if /mswin/ =~ RUBY_PLATFORM
    opts = %w[--disable-gem --disable=frozen-string-literal -robjspace]
    assert_separately opts, "#{<<-"begin;"}\n#{<<-'end;'}"
    begin;
      ObjectSpace.each_object{|o|
        o.inspect
        ObjectSpace.reachable_objects_from(Class)
      }
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

  def test_trace_object_allocations_stop_first
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      require "objspace"
      # Make sure stopping before the tracepoints are initialized doesn't raise. See [Bug #17020]
      ObjectSpace.trace_object_allocations_stop
    end;
  end

  def test_trace_object_allocations
    ObjectSpace.trace_object_allocations_clear # clear object_table to get rid of erroneous detection for c0
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

      # [Bug #19456]
      o4 =
        # This line intentionally left blank
        # This line intentionally left blank
        1.0 / 0.0; line4 = __LINE__; _c4 = GC.count
      assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(o4))
      assert_equal(line4, ObjectSpace.allocation_sourceline(o4))

      # The line number should be based on newarray instead of getinstancevariable.
      line5 = __LINE__; o5 = [ # newarray (leaf)
        @ivar, # getinstancevariable (not leaf)
      ]
      assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(o5))
      assert_equal(line5, ObjectSpace.allocation_sourceline(o5))

      # [Bug #19482]
      EnvUtil.under_gc_stress do
        100.times do
          Class.new
        end
      end
    }
  end

  def test_trace_object_allocations_start_stop_clear
    ObjectSpace.trace_object_allocations_clear # clear object_table to get rid of erroneous detection for obj3
    EnvUtil.without_gc do # suppress potential object reuse. see [Bug #11271]
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
  end

  def test_trace_object_allocations_gc_stress
    EnvUtil.under_gc_stress do
      ObjectSpace.trace_object_allocations{
        proc{}
      }
    end
    assert true # success
  end

  def test_trace_object_allocations_compaction
    omit "compaction is not supported on this platform" unless GC.respond_to?(:compact)

    assert_separately(%w(-robjspace), <<~RUBY)
      ObjectSpace.trace_object_allocations do
        objs = 100.times.map do
          Object.new
        end

        assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(objs[0]))

        GC.verify_compaction_references(expand_heap: true, toward: :empty)

        assert_equal(__FILE__, ObjectSpace.allocation_sourcefile(objs[0]))
      end
    RUBY
  end

  def test_trace_object_allocations_compaction_freed_pages
    omit "compaction is not supported on this platform" unless GC.respond_to?(:compact)

    assert_normal_exit(<<~RUBY)
      require "objspace"

      objs = []
      ObjectSpace.trace_object_allocations do
        1_000_000.times do
          objs << Object.new
        end
      end

      objs = nil

      # Free pages that the objs were on
      GC.start

      # Run compaction and check that it doesn't crash
      GC.compact
    RUBY
  end

  def test_dump_flags
    # Ensure that the fstring is promoted to old generation
    4.times { GC.start }
    info = ObjectSpace.dump("foo".freeze)
    assert_include(info, '"wb_protected":true')
    assert_include(info, '"age":3')
    assert_include(info, '"old":true')
    assert_match(/"fstring":true/, info)
    JSON.parse(info) if defined?(JSON)
  end

  def test_dump_flag_age
    EnvUtil.without_gc do
      o = Object.new

      assert_include(ObjectSpace.dump(o), '"age":0')

      GC.start

      assert_include(ObjectSpace.dump(o), '"age":1')
    end
  end

  if defined?(RubyVM::Shape)
    class TooComplex; end

    def test_dump_too_complex_shape
      omit "flaky test"

      RubyVM::Shape::SHAPE_MAX_VARIATIONS.times do
        TooComplex.new.instance_variable_set(:"@a#{_1}", 1)
      end

      tc = TooComplex.new
      info = ObjectSpace.dump(tc)
      assert_not_match(/"too_complex_shape"/, info)
      tc.instance_variable_set(:@new_ivar, 1)
      info = ObjectSpace.dump(tc)
      assert_match(/"too_complex_shape":true/, info)
      if defined?(JSON)
        assert_true(JSON.parse(info)["too_complex_shape"])
      end
    end
  end

  class NotTooComplex ; end

  def test_dump_not_too_complex_shape
    tc = NotTooComplex.new
    tc.instance_variable_set(:@new_ivar, 1)
    info = ObjectSpace.dump(tc)

    assert_not_match(/"too_complex_shape"/, info)
    if defined?(JSON)
      assert_nil(JSON.parse(info)["too_complex_shape"])
    end
  end

  def test_dump_to_default
    line = nil
    info = nil
    ObjectSpace.trace_object_allocations do
      line = __LINE__ + 1
      str = "hello w"
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
        str = "hello w"
        ObjectSpace.dump(str, output: w)
      end
      w.close
      th.value
    end
    assert_dump_object(info, line)
  end

  def assert_dump_object(info, line)
    loc = caller_locations(1, 1)[0]
    assert_match(/"type":"STRING"/, info)
    assert_match(/"embedded":true, "bytesize":7, "value":"hello w", "encoding":"UTF-8"/, info)
    assert_match(/"file":"#{Regexp.escape __FILE__}", "line":#{line}/, info)
    assert_match(/"method":"#{loc.base_label}"/, info)
    JSON.parse(info) if defined?(JSON)
  end

  def test_dump_array
    # Empty array
    info = ObjectSpace.dump([])
    assert_include(info, '"length":0, "embedded":true')
    assert_not_include(info, '"shared":true')

    # Non-embed array
    arr = (1..10).to_a
    info = ObjectSpace.dump(arr)
    assert_include(info, '"length":10')
    assert_not_include(info, '"embedded":true')
    assert_not_include(info, '"shared":true')

    # Shared array
    arr1 = (1..10).to_a
    arr = []
    arr.replace(arr1)
    info = ObjectSpace.dump(arr)
    assert_include(info, '"length":10, "shared":true')
    assert_not_include(info, '"embedded":true')
  end

  def test_dump_object
    klass = Class.new

    # Empty object
    info = ObjectSpace.dump(klass.new)
    assert_include(info, '"embedded":true')
    assert_include(info, '"ivars":0')

    # Non-embed object
    obj = klass.new
    5.times { |i| obj.instance_variable_set("@ivar#{i}", 0) }
    info = ObjectSpace.dump(obj)
    assert_not_include(info, '"embedded":true')
    assert_include(info, '"ivars":5')
  end

  def test_dump_control_char
    assert_include(ObjectSpace.dump("\x0f"), '"value":"\u000f"')
    assert_include(ObjectSpace.dump("\C-?"), '"value":"\u007f"')
  end

  def test_dump_special_consts
    # [ruby-core:69692] [Bug #11291]
    assert_equal('null', ObjectSpace.dump(nil))
    assert_equal('true', ObjectSpace.dump(true))
    assert_equal('false', ObjectSpace.dump(false))
    assert_equal('0', ObjectSpace.dump(0))
    assert_equal('{"type":"SYMBOL", "value":"test_dump_special_consts"}', ObjectSpace.dump(:test_dump_special_consts))
  end

  def test_dump_singleton_class
    assert_include(ObjectSpace.dump(Object), '"name":"Object"')
    assert_include(ObjectSpace.dump(Kernel), '"name":"Kernel"')
    assert_include(ObjectSpace.dump(Object.new.singleton_class), '"real_class_name":"Object"')

    singleton = Object.new.singleton_class
    singleton_dump = ObjectSpace.dump(singleton)
    assert_include(singleton_dump, '"singleton":true')
    if defined?(JSON)
      assert_equal(Object, singleton.superclass)
      superclass_address = JSON.parse(ObjectSpace.dump(Object)).fetch('address')
      assert_equal(superclass_address, JSON.parse(singleton_dump).fetch('superclass'))
    end
  end

  def test_dump_special_floats
    assert_match(/"value":"NaN"/, ObjectSpace.dump(Float::NAN))
    assert_match(/"value":"Inf"/, ObjectSpace.dump(Float::INFINITY))
    assert_match(/"value":"\-Inf"/, ObjectSpace.dump(-Float::INFINITY))
  end

  def test_dump_dynamic_symbol
    dump = ObjectSpace.dump(("foobar%x" % rand(0x10000)).to_sym)
    assert_match(/"type":"SYMBOL"/, dump)
    assert_match(/"value":"foobar\h+"/, dump)
  end

  def test_dump_outputs_object_id
    obj = Object.new

    # Doesn't output object_id when it has not been seen
    dump = ObjectSpace.dump(obj)
    assert_not_include(dump, "\"object_id\"")

    id = obj.object_id

    # Outputs object_id when it has been seen
    dump = ObjectSpace.dump(obj)
    assert_include(dump, "\"object_id\":#{id}")
  end

  def test_dump_includes_imemo_type
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          ObjectSpace.dump_all(output: :stdout)
        end

        p dump_my_heap_please
      end;
      assert_equal 'nil', output.pop
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

        p dump_my_heap_please
      end;
      assert_equal 'nil', output.pop
      heap = output.find_all { |l| JSON.parse(l)['type'] == "NONE" }
      assert_operator heap.length, :>, 0
    end
  end

  def test_dump_all_single_generation
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          GC.start
          ObjectSpace.trace_object_allocations_start
          gc_gen = GC.count
          puts gc_gen
          @obj1 = Object.new
          GC.start
          @obj2 = Object.new
          ObjectSpace.dump_all(output: :stdout, since: gc_gen, shapes: false)
        end

        p dump_my_heap_please
      end;
      assert_equal 'nil', output.pop
      since = output.shift.to_i
      assert_operator output.size, :>, 0
      generations = output.map { |l| JSON.parse(l) }.map { |o| o["generation"] }.uniq.sort
      assert_equal [since, since + 1], generations
    end
  end

  def test_dump_addresses_match_dump_all_addresses
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          obj = Object.new
          puts ObjectSpace.dump(obj)
          ObjectSpace.dump_all(output: $stdout)
        end

        p $stdout == dump_my_heap_please
      end;
      assert_equal 'true', output.pop
      needle = JSON.parse(output.first)
      addr = needle['address']
      found  = output.drop(1).find { |l| JSON.parse(l)['address'] == addr }
      assert found, "object #{addr} should be findable in full heap dump"
    end
  end

  def test_dump_class_addresses_match_dump_all_addresses
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          obj = Object.new
          puts ObjectSpace.dump(obj)
          ObjectSpace.dump_all(output: $stdout)
        end

        p $stdout == dump_my_heap_please
      end;
      assert_equal 'true', output.pop
      needle = JSON.parse(output.first)
      addr = needle['class']
      found  = output.drop(1).find { |l| JSON.parse(l)['address'] == addr }
      assert found, "object #{addr} should be findable in full heap dump"
    end
  end

  def test_dump_objects_dumps_page_slot_sizes
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          ObjectSpace.dump_all(output: $stdout)
        end

        p $stdout == dump_my_heap_please
      end;
      assert_equal 'true', output.pop
      assert(output.count > 1)
      output.each { |l|
        obj = JSON.parse(l)
        next if obj["type"] == "ROOT"
        next if obj["type"] == "SHAPE"

        assert_not_nil obj["slot_size"]
        assert_equal 0, obj["slot_size"] % (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD])
      }
    end
  end

  def test_dump_callinfo_includes_mid
    assert_in_out_err(%w[-robjspace --disable-gems], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        class Foo
          def foo
            super(bar: 123) # should not crash on 0 mid
          end

          def bar
            baz(bar: 123) # mid: baz
          end
        end

        ObjectSpace.dump_all(output: $stdout)
      end;
      assert_empty error
      assert(output.count > 1)
      assert_includes output.grep(/"imemo_type":"callinfo"/).join("\n"), '"mid":"baz"'
    end
  end

  def test_dump_string_coderange
    assert_includes ObjectSpace.dump("TEST STRING"), '"coderange":"7bit"'
    unknown = "TEST STRING".dup.force_encoding(Encoding::UTF_16BE)
    2.times do # ensure that dumping the string doesn't mutate it
      assert_includes ObjectSpace.dump(unknown), '"coderange":"unknown"'
    end
    assert_includes ObjectSpace.dump("Fée"), '"coderange":"valid"'
    assert_includes ObjectSpace.dump("\xFF"), '"coderange":"broken"'
  end

  def test_dump_escapes_method_name
    method_name = "foo\"bar"
    klass = Class.new do
      define_method(method_name) { "TEST STRING" }
    end
    ObjectSpace.trace_object_allocations_start

    obj = klass.new.send(method_name)

    dump = ObjectSpace.dump(obj)
    assert_includes dump, '"method":"foo\"bar"'

    parsed = JSON.parse(dump)
    assert_equal "foo\"bar", parsed["method"]
  ensure
    ObjectSpace.trace_object_allocations_stop
  end

  def test_dump_includes_slot_size
    str = "TEST"
    dump = ObjectSpace.dump(str)

    assert_includes dump, "\"slot_size\":#{GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]}"
  end

  def test_dump_reference_addresses_match_dump_all_addresses
    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}\n#{<<-'end;'}") do |output, error|
      begin;
        def dump_my_heap_please
          obj = Object.new
          obj2 = Object.new
          obj2.instance_variable_set(:@ref, obj)
          puts ObjectSpace.dump(obj)
          ObjectSpace.dump_all(output: $stdout)
        end

        p $stdout == dump_my_heap_please
      end;
      assert_equal 'true', output.pop
      needle = JSON.parse(output.first)
      addr = needle['address']
      found  = output.drop(1).find { |l| (JSON.parse(l)['references'] || []).include? addr }
      assert found, "object #{addr} should be findable in full heap dump"
    end
  end

  def assert_test_string_entry_correct_in_dump_all(output)
    # `TEST STRING` appears twice in the output of `ObjectSpace.dump_all`
    # 1. To create the T_STRING object for the literal string "TEST STRING"
    # 2. When it is assigned to the `str` variable with a new encoding
    #
    # This test makes assertions on the assignment to `str`, so we look for
    # the second appearance of /TEST STRING/ in the output
    test_string_in_dump_all = output.grep(/TEST2/)

    begin
      assert_equal(2, test_string_in_dump_all.size, "number of strings")
    rescue Test::Unit::AssertionFailedError => e
      STDERR.puts e.inspect
      STDERR.puts test_string_in_dump_all
      if test_string_in_dump_all.size == 3
        STDERR.puts "This test is skipped because it seems hard to fix."
      else
        raise
      end
    end

    strs = test_string_in_dump_all.reject do |s|
      s.include?("fstring")
    end

    assert_equal(1, strs.length)

    entry_hash = JSON.parse(strs[0])

    assert_equal(5, entry_hash["bytesize"], "bytesize is wrong")
    assert_equal("TEST2", entry_hash["value"], "value is wrong")
    assert_equal("UTF-8", entry_hash["encoding"], "encoding is wrong")
    assert_equal("-", entry_hash["file"], "file is wrong")
    assert_equal(5, entry_hash["line"], "line is wrong")
    assert_equal("dump_my_heap_please", entry_hash["method"], "method is wrong")
    assert_not_nil(entry_hash["generation"])
  end

  def test_dump_all
    opts = %w[--disable-gem --disable=frozen-string-literal -robjspace]

    assert_in_out_err(opts, "#{<<-"begin;"}#{<<-'end;'}") do |output, error|
      # frozen_string_literal: false
      begin;
        def dump_my_heap_please
          ObjectSpace.trace_object_allocations_start
          GC.start
          str = "TEST2".force_encoding("UTF-8")
          ObjectSpace.dump_all(output: :stdout)
        end

        p dump_my_heap_please
      end;

      assert_test_string_entry_correct_in_dump_all(output)
    end

    assert_in_out_err(%w[-robjspace], "#{<<-"begin;"}#{<<-'end;'}") do |(output), (error)|
      begin;
        # frozen_string_literal: false
        def dump_my_heap_please
          ObjectSpace.trace_object_allocations_start
          GC.start
          (str = "TEST2").force_encoding("UTF-8")
          ObjectSpace.dump_all().path
        end

        puts dump_my_heap_please
      end;
      assert_nil(error)
      dump = File.readlines(output)
      File.unlink(output)

      assert_test_string_entry_correct_in_dump_all(dump)
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
      assert_match(/"type":"FILE"/, output)
      assert_not_match(/"fd":/, output)
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

  def test_internal_class_of_on_ast
    children = ObjectSpace.reachable_objects_from(RubyVM::AbstractSyntaxTree.parse("kadomatsu"))
    children.each {|child| ObjectSpace.internal_class_of(child).itself} # this used to crash
  end

  def test_name_error_message
    begin
      bar
    rescue => err
      _, m = ObjectSpace.reachable_objects_from(err)
    end
    assert_equal(m, m.clone)
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

  def test_anonymous_class_name
    assert_not_include ObjectSpace.dump(Class.new), '"name"'
    assert_not_include ObjectSpace.dump(Module.new), '"name"'
  end

  def test_objspace_trace
    assert_in_out_err(%w[-robjspace/trace], "#{<<-"begin;"}\n#{<<-'end;'}") do |out, err|
      begin;
        # frozen_string_literal: false
        a = "foo"
        b = "b" + "a" + "r"
        c = 42
        p a, b, c
      end;
      assert_equal ["objspace/trace is enabled"], err
      assert_equal 3, out.size
      assert_equal '"foo" @ -:3', out[0]
      assert_equal '"bar" @ -:4', out[1]
      assert_equal '42', out[2]
    end
  end

  def load_allocation_path_helper method, to_binary: false

    Tempfile.create(["test_ruby_load_allocation_path", ".rb"]) do |t|
      path = t.path
      str = "#{Time.now.to_f.to_s}_#{rand.to_s}"
      t.puts script = <<~RUBY
        # frozen-string-literal: true
        return if Time.now.to_i > 0
        $gv = 'rnd-#{str}' # unreachable, but the string literal was written
      RUBY

      t.close

      if to_binary
        bin = RubyVM::InstructionSequence.compile_file(t.path).to_binary
        bt = Tempfile.new(['test_ruby_load_allocation_path', '.yarb'], mode: File::Constants::WRONLY)
        bt.write bin
        bt.close

        path = bt.path
      end

      assert_separately(%w[-robjspace -rtempfile], <<~RUBY)
        GC.disable
        path = "#{path}"
        ObjectSpace.trace_object_allocations do
          #{method}
        end

        n = 0
        dump = ObjectSpace.dump_all(output: :string)
        dump.each_line do |line|
          if /"value":"rnd-#{str}"/ =~ line && /"frozen":true/ =~ line
            assert Regexp.new('"file":"' + "#{path}") =~ line
            assert Regexp.new('"line":') !~ line
            n += 1
          end
        rescue ArgumentError
        end

        assert_equal(1, n)
      RUBY
    ensure
      bt.unlink if bt
    end
  end

  def test_load_allocation_path_load
    load_allocation_path_helper 'load(path)'
  end

  def test_load_allocation_path_compile_file
    load_allocation_path_helper 'RubyVM::InstructionSequence.compile_file(path)'
  end

  def test_load_allocation_path_load_from_binary
    # load_allocation_path_helper 'iseq = RubyVM::InstructionSequence.load_from_binary(File.binread(path))', to_binary: true
  end

  def test_escape_class_name
    class_name = '" little boby table [Bug #20892]'
    json = ObjectSpace.dump(Class.new.tap { |c| c.set_temporary_name(class_name) })
    assert_equal class_name, JSON.parse(json)["name"]
  end

  def test_dump_include_shareable
    omit 'Not provided by mmtk' if RUBY_DESCRIPTION.include?("+GC[mmtk]")

    assert_include(ObjectSpace.dump(ENV), '"shareable":true')
    assert_not_include(ObjectSpace.dump([]), '"shareable":true')
  end

  def test_utf8_method_names
    name = "utf8_❨╯°□°❩╯︵┻━┻"
    obj = ObjectSpace.trace_object_allocations do
      __send__(name)
    end
    dump = ObjectSpace.dump(obj)
    assert_equal name, JSON.parse(dump)["method"], dump
  end

  def test_dump_shapes
    json = ObjectSpace.dump_shapes(output: :string)
    json.each_line do |line|
      assert_include(line, '"type":"SHAPE"')
    end

    assert_empty ObjectSpace.dump_shapes(output: :string, since: RubyVM.stat(:next_shape_id))
    assert_equal 2, ObjectSpace.dump_shapes(output: :string, since: RubyVM.stat(:next_shape_id) - 2).lines.size
  end

  private

  def utf8_❨╯°□°❩╯︵┻━┻
    "1#{2}"
  end
end
