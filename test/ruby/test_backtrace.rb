# frozen_string_literal: false
require 'test/unit'
require 'tempfile'

class TestBacktrace < Test::Unit::TestCase
  def test_exception
    bt = Fiber.new{
      begin
        raise
      rescue => e
        e.backtrace
      end
    }.resume
    assert_equal(1, bt.size)
    assert_match(/.+:\d+:.+/, bt[0])
  end

  def helper_test_exception_backtrace_locations
    raise
  end

  def test_exception_backtrace_locations
    backtrace, backtrace_locations = Fiber.new{
      begin
        raise
      rescue => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})

    backtrace, backtrace_locations = Fiber.new{
      begin
        begin
          helper_test_exception_backtrace_locations
        rescue
          raise
        end
      rescue => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})
  end

  def call_helper_test_exception_backtrace_locations
    helper_test_exception_backtrace_locations(:bad_argument)
  end

  def test_argument_error_backtrace_locations
    backtrace, backtrace_locations = Fiber.new{
      begin
        helper_test_exception_backtrace_locations(1)
      rescue ArgumentError => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})

    backtrace, backtrace_locations = Fiber.new{
      begin
        call_helper_test_exception_backtrace_locations
      rescue ArgumentError => e
        [e.backtrace, e.backtrace_locations]
      end
    }.resume
    assert_equal(backtrace, backtrace_locations.map{|e| e.to_s})
  end

  def test_caller_lev
    cs = []
    Fiber.new{
      Proc.new{
        cs << caller(0)
        cs << caller(1)
        cs << caller(2)
        cs << caller(3)
        cs << caller(4)
        cs << caller(5)
      }.call
    }.resume
    assert_equal(2, cs[0].size)
    assert_equal(1, cs[1].size)
    assert_equal(0, cs[2].size)
    assert_equal(nil, cs[3])
    assert_equal(nil, cs[4])

    #
    max = 7
    rec = lambda{|n|
      if n > 0
        1.times{
          rec[n-1]
        }
      else
        (max*3).times{|i|
          total_size = caller(0).size
          c = caller(i)
          if c
            assert_equal(total_size - i, caller(i).size, "[ruby-dev:45673]")
          end
        }
      end
    }
    Fiber.new{
      rec[max]
    }.resume
  end

  def test_caller_lev_and_n
    m = 10
    rec = lambda{|n|
      if n < 0
        (m*6).times{|lev|
          (m*6).times{|i|
            t = caller(0).size
            r = caller(lev, i)
            r = r.size if r.respond_to? :size

            # STDERR.puts [t, lev, i, r].inspect
            if i == 0
              assert_equal(0, r, [t, lev, i, r].inspect)
            elsif t < lev
              assert_equal(nil, r, [t, lev, i, r].inspect)
            else
              if t - lev > i
                assert_equal(i, r, [t, lev, i, r].inspect)
              else
                assert_equal(t - lev, r, [t, lev, i, r].inspect)
              end
            end
          }
        }
      else
        rec[n-1]
      end
    }
    rec[m]
  end

  def test_caller_with_limit
    x = nil
    c = Class.new do
      define_method(:bar) do
        x = caller(1, 1)
      end
    end
    [c.new].group_by(&:bar)
    assert_equal 1, x.length
    assert_equal caller(0), caller(0, nil)
  end

  def test_caller_with_nil_length
    assert_equal caller(0), caller(0, nil)
  end

  def test_each_backtrace_location
    i = 0
    cl = caller_locations(1, 1)[0]; ecl = Thread.each_caller_location{|x| i+=1; break x if i == 1}
    assert_equal(cl.to_s, ecl.to_s)
    assert_kind_of(Thread::Backtrace::Location, ecl)

    i = 0
    ary = []
    cllr = caller_locations(1, 2); last = Thread.each_caller_location{|x| ary << x; i+=1; break x if i == 2}
    assert_equal(cllr.map(&:to_s), ary.map(&:to_s))
    assert_kind_of(Thread::Backtrace::Location, last)

    i = 0
    ary = []
    ->{->{
      cllr = caller_locations(1, 2); last = Thread.each_caller_location{|x| ary << x; i+=1; break x if i == 2}
    }.()}.()
    assert_equal(cllr.map(&:to_s), ary.map(&:to_s))
    assert_kind_of(Thread::Backtrace::Location, last)

    cllr = caller_locations(1, 2); ary = Thread.to_enum(:each_caller_location).to_a[2..3]
    assert_equal(cllr.map(&:to_s), ary.map(&:to_s))

    ecl = Thread.to_enum(:each_caller_location)
    assert_raise(StopIteration) {
      ecl.next
    }
  end

  def test_caller_locations_first_label
    def self.label
      caller_locations.first.label
    end

    def self.label_caller
      label
    end

    assert_equal 'label_caller', label_caller

    [1].group_by do
      assert_equal 'label_caller', label_caller
    end
  end

  def test_caller_limit_cfunc_iseq_no_pc
    def self.a; [1].group_by { b } end
    def self.b
      [
        caller_locations(2, 1).first.base_label,
        caller_locations(3, 1).first.base_label
      ]
    end
    assert_equal({["each", "group_by"]=>[1]}, a)
  end

  def test_caller_location_inspect_cfunc_iseq_no_pc
    def self.foo
      @res = caller_locations(2, 1).inspect
    end
    @line = __LINE__ + 1
    1.times.map { 1.times.map { foo } }
    assert_equal("[\"#{__FILE__}:#{@line}:in `times'\"]", @res)
  end

  def test_caller_location_path_cfunc_iseq_no_pc
    def self.foo
      @res = caller_locations(2, 1)[0].path
    end
    1.times.map { 1.times.map { foo } }
    assert_equal(__FILE__, @res)
  end

  def test_caller_locations
    cs = caller(0); locs = caller_locations(0).map{|loc|
      loc.to_s
    }
    assert_equal(cs, locs)
  end

  def test_caller_locations_with_range
    cs = caller(0,2); locs = caller_locations(0..1).map { |loc|
      loc.to_s
    }
    assert_equal(cs, locs)
  end

  def test_caller_locations_to_s_inspect
    cs = caller(0); locs = caller_locations(0)
    cs.zip(locs){|str, loc|
      assert_equal(str, loc.to_s)
      assert_equal(str.inspect, loc.inspect)
    }
  end

  def test_caller_locations_path
    loc, = caller_locations(0, 1)
    assert_equal(__FILE__, loc.path)
    Tempfile.create(%w"caller_locations .rb") do |f|
      f.puts "caller_locations(0, 1)[0].tap {|loc| puts loc.path}"
      f.close
      dir, base = File.split(f.path)
      assert_in_out_err(["-C", dir, base], "", [base])
    end
  end

  def test_caller_locations_absolute_path
    loc, = caller_locations(0, 1)
    assert_equal(__FILE__, loc.absolute_path)
    Tempfile.create(%w"caller_locations .rb") do |f|
      f.puts "caller_locations(0, 1)[0].tap {|loc| puts loc.absolute_path}"
      f.close
      assert_in_out_err(["-C", *File.split(f.path)], "", [File.realpath(f.path)])
    end
  end

  def test_caller_locations_lineno
    loc, = caller_locations(0, 1)
    assert_equal(__LINE__-1, loc.lineno)
    Tempfile.create(%w"caller_locations .rb") do |f|
      f.puts "caller_locations(0, 1)[0].tap {|loc| puts loc.lineno}"
      f.close
      assert_in_out_err(["-C", *File.split(f.path)], "", ["1"])
    end
  end

  def test_caller_locations_base_label
    assert_equal("#{__method__}", caller_locations(0, 1)[0].base_label)
    loc, = tap {break caller_locations(0, 1)}
    assert_equal("#{__method__}", loc.base_label)
    begin
      raise
    rescue
      assert_equal("#{__method__}", caller_locations(0, 1)[0].base_label)
    end
  end

  def test_caller_locations_label
    assert_equal("#{__method__}", caller_locations(0, 1)[0].label)
    loc, = tap {break caller_locations(0, 1)}
    assert_equal("block in #{__method__}", loc.label)
    begin
      raise
    rescue
      assert_equal("rescue in #{__method__}", caller_locations(0, 1)[0].label)
    end
  end

  def th_rec q, n=10
    if n > 1
      th_rec q, n-1
    else
      q.pop
    end
  end

  def test_thread_backtrace
    begin
      q = Thread::Queue.new
      th = Thread.new{
        th_rec q
      }
      sleep 0.5
      th_backtrace = th.backtrace
      th_locations = th.backtrace_locations

      assert_equal(10, th_backtrace.count{|e| e =~ /th_rec/})
      assert_equal(th_backtrace, th_locations.map{|e| e.to_s})
      assert_equal(th_backtrace, th.backtrace(0))
      assert_equal(th_locations.map{|e| e.to_s},
                   th.backtrace_locations(0).map{|e| e.to_s})
      th_backtrace.size.times{|n|
        assert_equal(n, th.backtrace(0, n).size)
        assert_equal(n, th.backtrace_locations(0, n).size)
      }
      n = th_backtrace.size
      assert_equal(n, th.backtrace(0, n + 1).size)
      assert_equal(n, th.backtrace_locations(0, n + 1).size)
    ensure
      q << true
      th.join
    end
  end

  def test_thread_backtrace_locations_with_range
    begin
      q = Thread::Queue.new
      th = Thread.new{
        th_rec q
      }
      sleep 0.5
      bt = th.backtrace(0,2)
      locs = th.backtrace_locations(0..1).map { |loc|
        loc.to_s
      }
      assert_equal(bt, locs)
    ensure
      q << true
      th.join
    end
  end

  def test_core_backtrace_alias
    obj = BasicObject.new
    e = assert_raise(NameError) do
      class << obj
        alias foo bar
      end
    end
    assert_not_match(/\Acore#/, e.backtrace_locations[0].base_label)
  end

  def test_core_backtrace_undef
    obj = BasicObject.new
    e = assert_raise(NameError) do
      class << obj
        undef foo
      end
    end
    assert_not_match(/\Acore#/, e.backtrace_locations[0].base_label)
  end

  def test_core_backtrace_hash_merge
    e = assert_raise(TypeError) do
      {**nil}
    end
    assert_not_match(/\Acore#/, e.backtrace_locations[0].base_label)
  end

  def test_notty_backtrace
    err = ["-:1:in `<main>': unhandled exception"]
    assert_in_out_err([], "raise", [], err)

    err = ["-:2:in `foo': foo! (RuntimeError)",
           "\tfrom -:4:in `<main>'"]
    assert_in_out_err([], <<-"end;", [], err)
    def foo
      raise "foo!"
    end
    foo
    end;

    err = ["-:7:in `rescue in bar': bar! (RuntimeError)",
           "\tfrom -:4:in `bar'",
           "\tfrom -:9:in `<main>'",
           "-:2:in `foo': foo! (RuntimeError)",
           "\tfrom -:5:in `bar'",
           "\tfrom -:9:in `<main>'"]
    assert_in_out_err([], <<-"end;", [], err)
    def foo
      raise "foo!"
    end
    def bar
      foo
    rescue
      raise "bar!"
    end
    bar
    end;
  end

  def test_caller_to_enum
    err = ["-:3:in `foo': unhandled exception", "\tfrom -:in `each'"]
    assert_in_out_err([], <<-"end;", [], err, "[ruby-core:91911]")
      def foo
        return to_enum(__method__) unless block_given?
        raise
        yield 1
      end

      enum = foo
      enum.next
    end;
  end

  def build_bt_prog(run_expr, frame_count: 1)
    capture_expr = "$captured_locs = caller_locations(0)"
    run_expr = run_expr.join("\n") if run_expr.is_a? Array
    run_expr ||= capture_expr
    <<~RUBY
      class SimpleExampleClass
        def ex_instance = #{capture_expr}
        def call_block_from_c = 1.times { #{capture_expr} }
        def call_block_twice_nested = 1.times { 1.times { #{capture_expr} } }
        def yield_nothing = yield
        def call_block_from_ruby = yield_nothing { #{capture_expr} }
        def instance_eval_string_from_ruby = instance_eval "ex_instance"
        def eval_string_from_ruby = eval #{capture_expr.inspect}
        alias aliased_ex_instance ex_instance

        define_method(:ex_bmethod) { #{capture_expr} }
        define_method(:call_block_from_bmethod) do
          1.times { #{capture_expr} }
        end

        1.times do
          define_method(:bmethod_defined_in_block) do
            1.times { #{capture_expr} }
          end
        end

        def ex_begin
          begin
            #{capture_expr}
          end
        end

        def ex_rescue
          begin
            raise "an exception"
          rescue
            #{capture_expr}
          end
        end

        def ex_ensure
          begin
            raise "an exception"
          rescue
            nil
          ensure
            #{capture_expr}
          end
        end

        class << self
          def ex_singleton = #{capture_expr}
          define_method(:ex_singleton_bmethod) { #{capture_expr} }
        end

        class NestedClass
          def nested_instance = #{capture_expr}
        end
      end

      module ModuleOne
        class NestedClass
          def nested_instance = #{capture_expr}
        end

        module_function
        def ex_module_function = #{capture_expr}
      end

      module MixedInModule
        def mixin_func = #{capture_expr}
      end
      class ClassWithMixin
        include MixedInModule
      end

      module TracepointTests
        def self.setup_tracepoint
          TracePoint.trace(:c_call) do |ev|
            #{capture_expr} if ev.method_id == :define_method
          end
        end
        def self.define_method_inside_tp
          setup_tracepoint
          define_method(:some_random_method) {}
        end
      end

      module ModuleWithExtendedHook
        def self.extended(other) = #{capture_expr}
      end

      object_with_singleton_method = Object.new.tap do |o|
        def o.test_method = #{capture_expr}
      end
      object_with_singleton_method.singleton_class.tap do |o|
        def o.double_singleton = #{capture_expr}
      end

      class EmptyClass
      end
      emptyclass_object_with_singleton_method = EmptyClass.new
      emptyclass_object_with_singleton_method.singleton_class.define_method(:test_method) do
        #{capture_expr}
      end

      module IntegerTestRefinement
        refine Integer do
          def refinement_method = #{capture_expr}
          def refinement_method_with_block = 1.times { #{capture_expr} }
        end

        refine Integer.singleton_class do
          def refinement_singleton = #{capture_expr}
        end
      end
      using IntegerTestRefinement

      class SimpleSuperclass
      end
      anonymous_class = Class.new do
        def test_method = #{capture_expr}
      end
      anonymous_subclass = Class.new(SimpleSuperclass) do
        def test_method = #{capture_expr}
        def self.singleton_test_method = #{capture_expr}
      end

      module IncludedModule
        def test_method = #{capture_expr}
      end
      class ClassWithIncludedModule
        include IncludedModule
      end

      #{run_expr}

      $captured_locs[0...#{frame_count}].each { puts _1.debug_label }
    RUBY
  end

  def test_debug_label_instance_method
    program = build_bt_prog("SimpleExampleClass.new.ex_instance")
    expected = ["SimpleExampleClass#ex_instance"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_singleton_method
    program = build_bt_prog("SimpleExampleClass.ex_singleton")
    expected = ["SimpleExampleClass.ex_singleton"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_class_nested_in_class
    program = build_bt_prog("SimpleExampleClass::NestedClass.new.nested_instance")
    expected = ["SimpleExampleClass::NestedClass#nested_instance"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_class_nested_in_module
    program = build_bt_prog("ModuleOne::NestedClass.new.nested_instance")
    expected = ["ModuleOne::NestedClass#nested_instance"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_block_from_ruby
    program = build_bt_prog("SimpleExampleClass.new.call_block_from_ruby", frame_count: 3)
    expected = [
      "block in SimpleExampleClass#call_block_from_ruby",
      "SimpleExampleClass#yield_nothing",
      "SimpleExampleClass#call_block_from_ruby",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_block_from_c
    program = build_bt_prog("SimpleExampleClass.new.call_block_from_c", frame_count: 3)
    expected = [
      "block in SimpleExampleClass#call_block_from_c",
      "Integer#times",
      "SimpleExampleClass#call_block_from_c",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_instance_eval
    program = build_bt_prog("SimpleExampleClass.new.instance_eval_string_from_ruby", frame_count: 4)
    expected = [
      "SimpleExampleClass#ex_instance",
      "eval in SimpleExampleClass#instance_eval_string_from_ruby",
      "BasicObject#instance_eval",
      "SimpleExampleClass#instance_eval_string_from_ruby",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_eval
    program = build_bt_prog("SimpleExampleClass.new.eval_string_from_ruby", frame_count: 3)
    expected = [
      "eval in SimpleExampleClass#eval_string_from_ruby",
      "Kernel#eval",
      "SimpleExampleClass#eval_string_from_ruby",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_main
    program = build_bt_prog(nil)
    expected = ["<main>"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_bmethod
    program = build_bt_prog("SimpleExampleClass.new.ex_bmethod")
    # n.b. - _all_ bmethods are actually blocks; the iseq never sheds it's blockiness
    # when it's passed to define_method.
    expected = ["block in SimpleExampleClass#ex_bmethod"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_block_in_bmethod
    program = build_bt_prog("SimpleExampleClass.new.call_block_from_bmethod", frame_count: 3)
    # Because of the above comment in test_debug_label_bmethod, there's actually no way
    # to differentiate a bmethod from a block inside a bmethod; both will have identical
    # output.
    expected = [
      "block (2 levels) in SimpleExampleClass#call_block_from_bmethod",
      "Integer#times",
      "block in SimpleExampleClass#call_block_from_bmethod",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_singleton_bmethod
    program = build_bt_prog("SimpleExampleClass.ex_singleton_bmethod")
    expected = ["block in SimpleExampleClass.ex_singleton_bmethod"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_defining_method_inside_tracepoint
    program = build_bt_prog("TracepointTests.define_method_inside_tp", frame_count: 3)
    expected = [
      "block in TracepointTests.setup_tracepoint",
      "TracepointTests.define_method_inside_tp",
      "<main>"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_inside_module_definition
    program = build_bt_prog("module DynModule; SimpleExampleClass.ex_singleton; end;", frame_count: 2)
    expected = [
      "SimpleExampleClass.ex_singleton",
      "<module:DynModule>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_inside_class_definition
    program = build_bt_prog(
      "module Nest; class DynClass; SimpleExampleClass.ex_singleton; end; end;",
      frame_count: 2
    )
    expected = [
      "SimpleExampleClass.ex_singleton",
      "<class:DynClass>",
    ]
    assert_in_out_err([], program, expected, [])
  end


  def test_debug_label_inside_anon_module_definition
    program = build_bt_prog("Module.new { SimpleExampleClass.ex_singleton }", frame_count: 2)
    expected = [
      "SimpleExampleClass.ex_singleton",
      "block in <main>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_module_extended_hook
    program = build_bt_prog("module DynModule; extend ModuleWithExtendedHook; end;", frame_count: 3)
    expected = [
      "ModuleWithExtendedHook.extended",
      "Kernel#extend",
      "<module:DynModule>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_toplevel_block
    program = build_bt_prog("Proc.new { SimpleExampleClass.ex_singleton }.call", frame_count: 2)
    expected = [
      "SimpleExampleClass.ex_singleton",
      "block in <main>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_singleton_object
    program = build_bt_prog("object_with_singleton_method.test_method")
    expected = ["#<instance of Object>.test_method"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_singleton_object_with_class
    program = build_bt_prog("emptyclass_object_with_singleton_method.test_method")
    expected = ["block in #<instance of EmptyClass>.test_method"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_module_function
    program = build_bt_prog("ModuleOne.ex_module_function")
    expected = ["ModuleOne.ex_module_function"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_refinement_method
    program = build_bt_prog("0.refinement_method", frame_count: 2)
    expected = [
      "#<refinement IntegerTestRefinement of Integer>#refinement_method",
      "<main>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_block_in_refinement_method
    program = build_bt_prog("0.refinement_method_with_block", frame_count: 4)
    expected = [
      "block in #<refinement IntegerTestRefinement of Integer>#refinement_method_with_block",
      "Integer#times",
      "#<refinement IntegerTestRefinement of Integer>#refinement_method_with_block",
      "<main>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_refinement_singleton_method
    program = build_bt_prog("Integer.refinement_singleton", frame_count: 2)
    expected = [
      "#<refinement IntegerTestRefinement of #<singleton of Integer>>#refinement_singleton",
      "<main>",
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_singleton_defined_on_singleton
    program = build_bt_prog("object_with_singleton_method.singleton_class.double_singleton")
    expected = ["#<singleton of #<instance of Object>>.double_singleton"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_anonymous_class
    program = build_bt_prog("anonymous_class.new.test_method")
    expected = ["#<anonymous subclass of Object>#test_method"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_anonymous_subclass
    program = build_bt_prog("anonymous_subclass.new.test_method")
    expected = ["#<anonymous subclass of SimpleSuperclass>#test_method"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_anonymous_subclass_singleton
    program = build_bt_prog("anonymous_subclass.singleton_test_method")
    expected = ["#<anonymous subclass of SimpleSuperclass>.singleton_test_method"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_included_module
    program = build_bt_prog("ClassWithIncludedModule.new.test_method")
    expected = ["IncludedModule#test_method"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_proc_alloc
    program = build_bt_prog([
      "Bug.proc_alloc_newobj_tp_setup",
      "lambda { 0 }"
    ], frame_count: 3);
    expected = [
      "Thread#backtrace_locations",
      "Kernel#lambda",
      "<main>"
    ]
    assert_in_out_err(["-I./.ext/#{RUBY_PLATFORM}/", "-r-test-/backtrace"], program, expected, [])
  end

  def test_debug_label_begin
    program = build_bt_prog("SimpleExampleClass.new.ex_begin")
    expected = ["SimpleExampleClass#ex_begin"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_rescue
    program = build_bt_prog("SimpleExampleClass.new.ex_rescue")
    expected = ["rescue in SimpleExampleClass#ex_rescue"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_ensure
    pend "This doesn't work; I can't actually seem to make an ISEQ_TYPE_ENSURE appear inside a method"
    program = build_bt_prog("SimpleExampleClass.new.ex_ensure")
    expected = ["ensure in SimpleExampleClass#ex_ensure"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_toplevel_rescue
    program = build_bt_prog(
      "begin; raise 'hi'; rescue; SimpleExampleClass.ex_singleton; end;",
      frame_count: 2
    )
    expected = [
      "SimpleExampleClass.ex_singleton",
      "rescue in <main>"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_toplevel_ensure
    program = build_bt_prog(
      "begin; $do = :nothing; ensure; SimpleExampleClass.ex_singleton; end;",
      frame_count: 2
    )
    expected = [
      "SimpleExampleClass.ex_singleton",
      "<main>"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_toplevel_eval
    program = build_bt_prog("eval \"SimpleExampleClass.ex_singleton\"", frame_count: 4);
    expected = [
      "SimpleExampleClass.ex_singleton",
      "<main>",
      "Kernel#eval",
      "<main>"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_toplevel_nested_eval
    string = "SimpleExampleClass.ex_singleton"
    program = build_bt_prog("eval #{"eval #{string.inspect}".inspect}", frame_count: 6);
    expected = [
      "SimpleExampleClass.ex_singleton",
      "<main>",
      "Kernel#eval",
      "<main>",
      "Kernel#eval",
      "<main>"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_bmethod_defined_in_block
    program = build_bt_prog("SimpleExampleClass.new.bmethod_defined_in_block", frame_count: 4)
    expected = [
      "block (3 levels) in SimpleExampleClass#bmethod_defined_in_block",
      "Integer#times",
      "block (2 levels) in SimpleExampleClass#bmethod_defined_in_block",
      "<main>"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_block_nested_in_method
    program = build_bt_prog("SimpleExampleClass.new.call_block_twice_nested", frame_count: 5)
    expected = [
      "block (2 levels) in SimpleExampleClass#call_block_twice_nested",
      "Integer#times",
      "block in SimpleExampleClass#call_block_twice_nested",
      "Integer#times",
      "SimpleExampleClass#call_block_twice_nested"
    ]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_aliased_method
    program = build_bt_prog("SimpleExampleClass.new.aliased_ex_instance")
    expected = ["SimpleExampleClass#ex_instance"]
    assert_in_out_err([], program, expected, [])
  end

  def test_debug_label_included_method
    program = build_bt_prog("ClassWithMixin.new.mixin_func")
    expected = ["MixedInModule#mixin_func"]
    assert_in_out_err([], program, expected, [])
  end
end
