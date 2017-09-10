# frozen_string_literal: false
require 'test/unit'

class TestGc < Test::Unit::TestCase
  class S
    def initialize(a)
      @a = a
    end
  end

  def test_gc
    prev_stress = GC.stress
    GC.stress = false

    assert_nothing_raised do
      tmp = nil
      1.upto(10000) {
        tmp = [0,1,2,3,4,5,6,7,8,9]
      }
    end
    l=nil
    100000.times {
      l = S.new(l)
    }
    GC.start
    assert true   # reach here or dumps core
    l = []
    100000.times {
      l.push([l])
    }
    GC.start
    assert true   # reach here or dumps core

    GC.stress = prev_stress
  end

  def use_rgengc?
    GC::OPTS.include? 'USE_RGENGC'.freeze
  end

  def test_enable_disable
    GC.enable
    assert_equal(false, GC.enable)
    assert_equal(false, GC.disable)
    assert_equal(true, GC.disable)
    assert_equal(true, GC.disable)
    assert_nil(GC.start)
    assert_equal(true, GC.enable)
    assert_equal(false, GC.enable)
  ensure
    GC.enable
  end

  def test_start_full_mark
    return unless use_rgengc?

    GC.start(full_mark: false)
    assert_nil GC.latest_gc_info(:major_by)

    GC.start(full_mark: true)
    assert_not_nil GC.latest_gc_info(:major_by)
  end

  def test_start_immediate_sweep
    GC.start(immediate_sweep: false)
    assert_equal false, GC.latest_gc_info(:immediate_sweep)

    GC.start(immediate_sweep: true)
    assert_equal true, GC.latest_gc_info(:immediate_sweep)
  end

  def test_count
    c = GC.count
    GC.start
    assert_operator(c, :<, GC.count)
  end

  def test_stat
    res = GC.stat
    assert_equal(false, res.empty?)
    assert_kind_of(Integer, res[:count])

    arg = Hash.new
    res = GC.stat(arg)
    assert_equal(arg, res)
    assert_equal(false, res.empty?)
    assert_kind_of(Integer, res[:count])

    stat, count = {}, {}
    GC.start
    GC.stat(stat)
    ObjectSpace.count_objects(count)
    assert_equal(count[:TOTAL]-count[:FREE], stat[:heap_live_slots])
    assert_equal(count[:FREE], stat[:heap_free_slots])

    # measure again without GC.start
    1000.times{ "a" + "b" }
    GC.stat(stat)
    ObjectSpace.count_objects(count)
    assert_equal(count[:FREE], stat[:heap_free_slots])
  end

  def test_stat_argument
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) {GC.stat(:"\u{30eb 30d3 30fc}")}
  end

  def test_stat_single
    stat = GC.stat
    assert_equal stat[:count], GC.stat(:count)
    assert_raise(ArgumentError){ GC.stat(:invalid) }
  end

  def test_stat_constraints
    stat = GC.stat
    assert_equal stat[:total_allocated_pages], stat[:heap_allocated_pages] + stat[:total_freed_pages]
    assert_operator stat[:heap_sorted_length], :>=, stat[:heap_eden_pages] + stat[:heap_allocatable_pages], "stat is: " + stat.inspect
    assert_equal stat[:heap_available_slots], stat[:heap_live_slots] + stat[:heap_free_slots] + stat[:heap_final_slots]
    assert_equal stat[:heap_live_slots], stat[:total_allocated_objects] - stat[:total_freed_objects] - stat[:heap_final_slots]
    assert_equal stat[:heap_allocated_pages], stat[:heap_eden_pages] + stat[:heap_tomb_pages]

    if use_rgengc?
      assert_equal stat[:count], stat[:major_gc_count] + stat[:minor_gc_count]
    end
  end

  def test_latest_gc_info
    assert_separately %w[--disable-gem], __FILE__, __LINE__, <<-'eom'
    GC.start
    count = GC.stat(:heap_free_slots) + GC.stat(:heap_allocatable_pages) * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT]
    count.times{ "a" + "b" }
    assert_equal :newobj, GC.latest_gc_info[:gc_by]
    eom

    GC.start
    assert_equal :force, GC.latest_gc_info[:major_by] if use_rgengc?
    assert_equal :method, GC.latest_gc_info[:gc_by]
    assert_equal true, GC.latest_gc_info[:immediate_sweep]

    GC.stress = true
    assert_equal :force, GC.latest_gc_info[:major_by]
  ensure
    GC.stress = false
  end

  def test_latest_gc_info_argument
    info = {}
    GC.latest_gc_info(info)

    assert_not_empty info
    assert_equal info[:gc_by], GC.latest_gc_info(:gc_by)
    assert_raise(ArgumentError){ GC.latest_gc_info(:invalid) }
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) {GC.latest_gc_info(:"\u{30eb 30d3 30fc}")}
  end

  def test_singleton_method
    assert_in_out_err(%w[--disable-gems], <<-EOS, [], [], "[ruby-dev:42832]")
      GC.stress = true
      10.times do
        obj = Object.new
        def obj.foo() end
        def obj.bar() raise "obj.foo is called, but this is obj.bar" end
        obj.foo
      end
    EOS
  end

  def test_singleton_method_added
    assert_in_out_err(%w[--disable-gems], <<-EOS, [], [], "[ruby-dev:44436]")
      class BasicObject
        undef singleton_method_added
        def singleton_method_added(mid)
          raise
        end
      end
      b = proc {}
      class << b; end
      b.clone rescue nil
      GC.start
    EOS
  end

  def test_gc_parameter
    env = {
      "RUBY_GC_MALLOC_LIMIT" => "60000000",
      "RUBY_GC_HEAP_INIT_SLOTS" => "100000"
    }
    assert_normal_exit("exit", "[ruby-core:39777]", :child_env => env)

    env = {
      "RUBYOPT" => "",
      "RUBY_GC_HEAP_INIT_SLOTS" => "100000"
    }
    assert_in_out_err([env, "-e", "exit"], "", [], [], "[ruby-core:39795]")
    assert_in_out_err([env, "-W0", "-e", "exit"], "", [], [], "[ruby-core:39795]")
    assert_in_out_err([env, "-W1", "-e", "exit"], "", [], [], "[ruby-core:39795]")
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_INIT_SLOTS=100000/, "[ruby-core:39795]")

    env = {
      "RUBY_GC_HEAP_GROWTH_FACTOR" => "2.0",
      "RUBY_GC_HEAP_GROWTH_MAX_SLOTS" => "10000"
    }
    assert_normal_exit("exit", "", :child_env => env)
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_GROWTH_FACTOR=2.0/, "")
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_GROWTH_MAX_SLOTS=10000/, "[ruby-core:57928]")

    env = {
      "RUBY_GC_HEAP_INIT_SLOTS" => "100000",
      "RUBY_GC_HEAP_FREE_SLOTS" => "10000",
      "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "0.9",
    }
    assert_normal_exit("exit", "", :child_env => env)
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR=0\.9/, "")

    # always full GC when RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR < 1.0
    assert_in_out_err([env, "-e", "1000_000.times{Object.new}; p(GC.stat[:minor_gc_count] < GC.stat[:major_gc_count])"], "", ['true'], //, "") if use_rgengc?

    # check obsolete
    assert_in_out_err([{'RUBY_FREE_MIN' => '100'}, '-w', '-eexit'], '', [],
      /RUBY_FREE_MIN is obsolete. Use RUBY_GC_HEAP_FREE_SLOTS instead/)
    assert_in_out_err([{'RUBY_HEAP_MIN_SLOTS' => '100'}, '-w', '-eexit'], '', [],
      /RUBY_HEAP_MIN_SLOTS is obsolete. Use RUBY_GC_HEAP_INIT_SLOTS instead/)

    env = {
      "RUBY_GC_MALLOC_LIMIT"               => "60000000",
      "RUBY_GC_MALLOC_LIMIT_MAX"           => "160000000",
      "RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR" => "2.0"
    }
    assert_normal_exit("exit", "", :child_env => env)
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_MALLOC_LIMIT=6000000/, "")
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_MALLOC_LIMIT_MAX=16000000/, "")
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_MALLOC_LIMIT_GROWTH_FACTOR=2.0/, "")

    if use_rgengc?
      env = {
        "RUBY_GC_OLDMALLOC_LIMIT"               => "60000000",
        "RUBY_GC_OLDMALLOC_LIMIT_MAX"           => "160000000",
        "RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR" => "2.0"
      }
      assert_normal_exit("exit", "", :child_env => env)
      assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_OLDMALLOC_LIMIT=6000000/, "")
      assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_OLDMALLOC_LIMIT_MAX=16000000/, "")
      assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_OLDMALLOC_LIMIT_GROWTH_FACTOR=2.0/, "")
    end
  end

  def test_profiler_enabled
    GC::Profiler.enable
    assert_equal(true, GC::Profiler.enabled?)
    GC::Profiler.disable
    assert_equal(false, GC::Profiler.enabled?)
  ensure
    GC::Profiler.disable
  end

  def test_profiler_clear
    assert_separately %w[--disable-gem], __FILE__, __LINE__, <<-'eom', timeout: 30
    GC::Profiler.enable

    GC.start
    assert_equal(1, GC::Profiler.raw_data.size)
    GC::Profiler.clear
    assert_equal(0, GC::Profiler.raw_data.size)

    200.times{ GC.start }
    assert_equal(200, GC::Profiler.raw_data.size)
    GC::Profiler.clear
    assert_equal(0, GC::Profiler.raw_data.size)
    eom
  end

  def test_profiler_total_time
    GC::Profiler.enable
    GC::Profiler.clear

    GC.start
    assert_operator(GC::Profiler.total_time, :>=, 0)
  ensure
    GC::Profiler.disable
  end

  def test_finalizing_main_thread
    assert_in_out_err(%w[--disable-gems], <<-EOS, ["\"finalize\""], [], "[ruby-dev:46647]")
      ObjectSpace.define_finalizer(Thread.main) { p 'finalize' }
    EOS
  end

  def test_expand_heap
    assert_separately %w[--disable-gem], __FILE__, __LINE__, <<-'eom'
    GC.start
    base_length = GC.stat[:heap_eden_pages]
    (base_length * 500).times{ 'a' }
    GC.start
    assert_in_delta base_length, (v = GC.stat[:heap_eden_pages]), 2,
           "invalid heap expanding (base_length: #{base_length}, GC.stat[:heap_eden_pages]: #{v})"

    a = []
    (base_length * 500).times{ a << 'a'; nil }
    GC.start
    assert_operator base_length, :<, GC.stat[:heap_eden_pages] + 1
    eom
  end

  def test_gc_internals
    assert_not_nil GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT]
    assert_not_nil GC::INTERNAL_CONSTANTS[:RVALUE_SIZE]
  end

  def test_sweep_in_finalizer
    bug9205 = '[ruby-core:58833] [Bug #9205]'
    2.times do
      assert_ruby_status([], <<-'end;', bug9205, timeout: 60)
        raise_proc = proc do |id|
          GC.start
        end
        1000.times do
          ObjectSpace.define_finalizer(Object.new, raise_proc)
        end
      end;
    end
  end

  def test_exception_in_finalizer
    bug9168 = '[ruby-core:58652] [Bug #9168]'
    assert_normal_exit(<<-'end;', bug9168, encoding: Encoding::ASCII_8BIT)
      raise_proc = proc {raise}
      10000.times do
        ObjectSpace.define_finalizer(Object.new, raise_proc)
        Thread.handle_interrupt(RuntimeError => :immediate) {break}
        Thread.handle_interrupt(RuntimeError => :on_blocking) {break}
        Thread.handle_interrupt(RuntimeError => :never) {break}
      end
    end;
  end

  def test_interrupt_in_finalizer
    bug10595 = '[ruby-core:66825] [Bug #10595]'
    src = <<-'end;'
      Signal.trap(:INT, 'DEFAULT')
      pid = $$
      Thread.start do
        10.times {
          sleep 0.1
          Process.kill("INT", pid) rescue break
        }
      end
      f = proc {1000.times {}}
      loop do
        ObjectSpace.define_finalizer(Object.new, f)
      end
    end;
    out, err, status = assert_in_out_err(["-e", src], "", [], [], bug10595, signal: :SEGV) do |*result|
      break result
    end
    unless /mswin|mingw/ =~ RUBY_PLATFORM
      assert_equal("INT", Signal.signame(status.termsig), bug10595)
    end
    assert_match(/Interrupt/, err.first, proc {err.join("\n")})
    assert_empty(out)
  end

  def test_verify_internal_consistency
    assert_nil(GC.verify_internal_consistency)
  end

  def test_gc_stress_on_realloc
    assert_normal_exit(<<-'end;', '[Bug #9859]')
      class C
        def initialize
          @a = nil
          @b = nil
          @c = nil
          @d = nil
          @e = nil
          @f = nil
        end
      end

      GC.stress = true
      C.new
    end;
  end

  def test_gc_disabled_start
    begin
      disabled = GC.disable
      c = GC.count
      GC.start
      assert_equal 1, GC.count - c
    ensure
      GC.enable unless disabled
    end
  end

  def test_vm_object
    assert_normal_exit <<-'end', '[Bug #12583]'
      ObjectSpace.each_object{|o| o.singleton_class rescue 0}
      ObjectSpace.each_object{|o| case o when Module then o.instance_methods end}
    end
  end

  def test_exception_in_finalizer_method
    @result = []
    def self.c1(x)
      @result << :c1
      raise
    end
    def self.c2(x)
      @result << :c2
      raise
    end
    tap {
      tap {
        obj = Object.new
        ObjectSpace.define_finalizer(obj, method(:c1))
        ObjectSpace.define_finalizer(obj, method(:c2))
        obj = nil
      }
    }
    GC.start
    skip "finalizers did not get run" if @result.empty?
    assert_equal([:c1, :c2], @result)
  end
end
