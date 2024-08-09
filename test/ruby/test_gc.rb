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
      tmp
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

  def test_gc_config_full_mark_by_default
    omit "unsupoported platform/GC" unless defined?(GC.config)

    config = GC.config
    assert_not_empty(config)
    assert_true(config[:rgengc_allow_full_mark])
  end

  def test_gc_config_invalid_args
    omit "unsupoported platform/GC" unless defined?(GC.config)

    assert_raise(ArgumentError) { GC.config(0) }
  end

  def test_gc_config_setting_returns_updated_config_hash
    omit "unsupoported platform/GC" unless defined?(GC.config)

    old_value = GC.config[:rgengc_allow_full_mark]
    assert_true(old_value)

    new_value = GC.config(rgengc_allow_full_mark: false)[:rgengc_allow_full_mark]
    assert_false(new_value)
    new_value = GC.config(rgengc_allow_full_mark: nil)[:rgengc_allow_full_mark]
    assert_false(new_value)
  ensure
    GC.config(rgengc_allow_full_mark: old_value)
    GC.start
  end

  def test_gc_config_setting_returns_nil_for_missing_keys
    omit "unsupoported platform/GC" unless defined?(GC.config)

    missing_value = GC.config(no_such_key: true)[:no_such_key]
    assert_nil(missing_value)
  ensure
    GC.config(full_mark: true)
    GC.start
  end

  def test_gc_config_disable_major
    omit "unsupoported platform/GC" unless defined?(GC.config)

    GC.enable
    GC.start

    GC.config(rgengc_allow_full_mark: false)
    major_count = GC.stat[:major_gc_count]
    minor_count = GC.stat[:minor_gc_count]

    arr = []
    (GC.stat_heap[0][:heap_eden_slots] * 2).times do
      arr << Object.new
      Object.new
    end

    assert_equal(major_count, GC.stat[:major_gc_count])
    assert_operator(minor_count, :<=, GC.stat[:minor_gc_count])
    assert_nil(GC.start)
  ensure
    GC.config(rgengc_allow_full_mark: true)
    GC.start
  end

  def test_gc_config_disable_major_gc_start_always_works
    omit "unsupoported platform/GC" unless defined?(GC.config)

    GC.config(full_mark: false)

    major_count = GC.stat[:major_gc_count]
    GC.start

    assert_operator(major_count, :<, GC.stat[:major_gc_count])
  ensure
    GC.config(full_mark: true)
    GC.start
  end

  def test_start_full_mark
    return unless use_rgengc?
    omit 'stress' if GC.stress

    3.times { GC.start } # full mark and next time it should be minor mark
    GC.start(full_mark: false)
    assert_nil GC.latest_gc_info(:major_by)

    GC.start(full_mark: true)
    assert_not_nil GC.latest_gc_info(:major_by)
  end

  def test_start_immediate_sweep
    omit 'stress' if GC.stress

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
    2.times{ # to ignore const cache imemo creation
      GC.start
      GC.stat(stat)
      ObjectSpace.count_objects(count)
      # repeat same methods invocation for cache object creation.
      GC.stat(stat)
      ObjectSpace.count_objects(count)
    }
    assert_equal(count[:TOTAL]-count[:FREE], stat[:heap_live_slots])
    assert_equal(count[:FREE], stat[:heap_free_slots])

    # measure again without GC.start
    2.times{ # to ignore const cache imemo creation
      1000.times{ "a" + "b" }
      GC.stat(stat)
      ObjectSpace.count_objects(count)
    }
    assert_equal(count[:FREE], stat[:heap_free_slots])
  end

  def test_stat_argument
    assert_raise_with_message(ArgumentError, /\u{30eb 30d3 30fc}/) {GC.stat(:"\u{30eb 30d3 30fc}")}
  end

  def test_stat_single
    omit 'stress' if GC.stress

    stat = GC.stat
    assert_equal stat[:count], GC.stat(:count)
    assert_raise(ArgumentError){ GC.stat(:invalid) }
  end

  def test_stat_constraints
    omit 'stress' if GC.stress

    stat = GC.stat
    # marking_time + sweeping_time could differ from time by 1 because they're stored in nanoseconds
    assert_in_delta stat[:time], stat[:marking_time] + stat[:sweeping_time], 1
    assert_equal stat[:total_allocated_pages], stat[:heap_allocated_pages] + stat[:total_freed_pages]
    assert_operator stat[:heap_sorted_length], :>=, stat[:heap_eden_pages] + stat[:heap_allocatable_pages], "stat is: " + stat.inspect
    assert_equal stat[:heap_available_slots], stat[:heap_live_slots] + stat[:heap_free_slots] + stat[:heap_final_slots]
    assert_equal stat[:heap_live_slots], stat[:total_allocated_objects] - stat[:total_freed_objects] - stat[:heap_final_slots]
    assert_equal stat[:heap_allocated_pages], stat[:heap_eden_pages] + stat[:heap_tomb_pages]

    if use_rgengc?
      assert_equal stat[:count], stat[:major_gc_count] + stat[:minor_gc_count]
    end
  end

  def test_stat_heap
    omit 'stress' if GC.stress

    stat_heap = {}
    stat = {}
    # Initialize to prevent GC in future calls
    GC.stat_heap(0, stat_heap)
    GC.stat(stat)

    GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT].times do |i|
      begin
        reenable_gc = !GC.disable
        GC.stat_heap(i, stat_heap)
        GC.stat(stat)
      ensure
        GC.enable if reenable_gc
      end

      assert_equal (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD]) * (2**i), stat_heap[:slot_size]
      assert_operator stat_heap[:heap_allocatable_pages], :<=, stat[:heap_allocatable_pages]
      assert_operator stat_heap[:heap_eden_pages], :<=, stat[:heap_eden_pages]
      assert_operator stat_heap[:heap_eden_slots], :>=, 0
      assert_operator stat_heap[:heap_tomb_pages], :<=, stat[:heap_tomb_pages]
      assert_operator stat_heap[:heap_tomb_slots], :>=, 0
      assert_operator stat_heap[:total_allocated_pages], :>=, 0
      assert_operator stat_heap[:total_freed_pages], :>=, 0
      assert_operator stat_heap[:force_major_gc_count], :>=, 0
      assert_operator stat_heap[:force_incremental_marking_finish_count], :>=, 0
      assert_operator stat_heap[:total_allocated_objects], :>=, 0
      assert_operator stat_heap[:total_freed_objects], :>=, 0
      assert_operator stat_heap[:total_freed_objects], :<=, stat_heap[:total_allocated_objects]
    end

    GC.stat_heap(0, stat_heap)
    assert_equal stat_heap[:slot_size], GC.stat_heap(0, :slot_size)
    assert_equal stat_heap[:slot_size], GC.stat_heap(0)[:slot_size]

    assert_raise(ArgumentError) { GC.stat_heap(-1) }
    assert_raise(ArgumentError) { GC.stat_heap(GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT]) }
  end

  def test_stat_heap_all
    omit "flaky with RJIT, which allocates objects itself" if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?
    stat_heap_all = {}
    stat_heap = {}
    # Initialize to prevent GC in future calls
    GC.stat_heap(0, stat_heap)
    GC.stat_heap(nil, stat_heap_all)

    GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT].times do |i|
      GC.stat_heap(nil, stat_heap_all)
      GC.stat_heap(i, stat_heap)

      # Remove keys that can vary between invocations
      %i(total_allocated_objects).each do |sym|
        stat_heap[sym] = stat_heap_all[i][sym] = 0
      end

      assert_equal stat_heap, stat_heap_all[i]
    end

    assert_raise(TypeError) { GC.stat_heap(nil, :slot_size) }
  end

  def test_stat_heap_constraints
    omit 'stress' if GC.stress

    stat = GC.stat
    stat_heap = GC.stat_heap
    2.times do
      GC.stat(stat)
      GC.stat_heap(nil, stat_heap)
    end

    stat_heap_sum = Hash.new(0)
    stat_heap.values.each do |hash|
      hash.each { |k, v| stat_heap_sum[k] += v }
    end

    assert_equal stat[:heap_allocatable_pages], stat_heap_sum[:heap_allocatable_pages]
    assert_equal stat[:heap_eden_pages], stat_heap_sum[:heap_eden_pages]
    assert_equal stat[:heap_tomb_pages], stat_heap_sum[:heap_tomb_pages]
    assert_equal stat[:heap_available_slots], stat_heap_sum[:heap_eden_slots] + stat_heap_sum[:heap_tomb_slots]
    assert_equal stat[:total_allocated_pages], stat_heap_sum[:total_allocated_pages]
    assert_equal stat[:total_freed_pages], stat_heap_sum[:total_freed_pages]
    assert_equal stat[:total_allocated_objects], stat_heap_sum[:total_allocated_objects]
    assert_equal stat[:total_freed_objects], stat_heap_sum[:total_freed_objects]
  end

  def test_measure_total_time
    assert_separately([], __FILE__, __LINE__, <<~RUBY)
      GC.measure_total_time = false

      time_before = GC.stat(:time)

      # Generate some garbage
      Random.new.bytes(100 * 1024 * 1024)
      GC.start

      time_after = GC.stat(:time)

      # If time measurement is disabled, the time stat should not change
      assert_equal time_before, time_after
    RUBY
  end

  def test_latest_gc_info
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<-'RUBY')
      GC.start
      count = GC.stat(:heap_free_slots) + GC.stat(:heap_allocatable_pages) * GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT]
      count.times{ "a" + "b" }
      assert_equal :newobj, GC.latest_gc_info[:gc_by]
    RUBY

    GC.latest_gc_info(h = {}) # allocate hash and rehearsal
    GC.start
    GC.start
    GC.start
    GC.latest_gc_info(h)

    assert_equal :force,  h[:major_by] if use_rgengc?
    assert_equal :method, h[:gc_by]
    assert_equal true,    h[:immediate_sweep]
    assert_equal true,    h.key?(:need_major_by)

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

  def test_latest_gc_info_need_major_by
    return unless use_rgengc?
    omit 'stress' if GC.stress

    3.times { GC.start }
    assert_nil GC.latest_gc_info(:need_major_by)

    # allocate objects until need_major_by is set or major GC happens
    objects = []
    while GC.latest_gc_info(:need_major_by).nil?
      objects.append(100.times.map { '*' })
    end

    # We need to ensure that no GC gets ran before the call to GC.start since
    # it would trigger a major GC. Assertions could allocate objects and
    # trigger a GC so we don't run assertions until we perform the major GC.
    need_major_by = GC.latest_gc_info(:need_major_by)
    GC.start(full_mark: false) # should be upgraded to major
    major_by = GC.latest_gc_info(:major_by)

    assert_not_nil(need_major_by)
    assert_not_nil(major_by)
  end

  def test_latest_gc_info_weak_references_count
    assert_separately([], __FILE__, __LINE__, <<~RUBY)
      count = 10_000
      # Some weak references may be created, so allow some margin of error
      error_tolerance = 100

      # Run full GC to clear out weak references
      GC.start
      # Run full GC again to collect stats about weak references
      GC.start

      before_weak_references_count = GC.latest_gc_info(:weak_references_count)
      before_retained_weak_references_count = GC.latest_gc_info(:retained_weak_references_count)

      # Create some objects and place it in a WeakMap
      wmap = ObjectSpace::WeakMap.new
      ary = Array.new(count)
      enum = count.times
      enum.each.with_index do |i|
        obj = Object.new
        ary[i] = obj
        wmap[obj] = nil
      end

      # Run full GC to collect stats about weak references
      GC.start

      assert_operator(GC.latest_gc_info(:weak_references_count), :>=, before_weak_references_count + count - error_tolerance)
      assert_operator(GC.latest_gc_info(:retained_weak_references_count), :>=, before_retained_weak_references_count + count - error_tolerance)
      assert_operator(GC.latest_gc_info(:retained_weak_references_count), :<=, GC.latest_gc_info(:weak_references_count))

      before_weak_references_count = GC.latest_gc_info(:weak_references_count)
      before_retained_weak_references_count = GC.latest_gc_info(:retained_weak_references_count)

      ary = nil

      # Free ary, which should empty out the wmap
      GC.start
      # Run full GC again to collect stats about weak references
      GC.start

      # Sometimes the WeakMap has one element, which might be held on by registers.
      assert_operator(wmap.size, :<=, 1)

      assert_operator(GC.latest_gc_info(:weak_references_count), :<=, before_weak_references_count - count + error_tolerance)
      assert_operator(GC.latest_gc_info(:retained_weak_references_count), :<=, before_retained_weak_references_count - count + error_tolerance)
      assert_operator(GC.latest_gc_info(:retained_weak_references_count), :<=, GC.latest_gc_info(:weak_references_count))
    RUBY
  end

  def test_stress_compile_send
    assert_in_out_err([], <<-EOS, [], [], "")
      GC.stress = true
      begin
        eval("A::B.c(1, 1, d: 234)")
      rescue
      end
    EOS
  end

  def test_singleton_method
    assert_in_out_err([], <<-EOS, [], [], "[ruby-dev:42832]")
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
    assert_in_out_err([], <<-EOS, [], [], "[ruby-dev:44436]")
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
      "RUBY_GC_HEAP_INIT_SLOTS" => "100"
    }
    assert_in_out_err([env, "-W0", "-e", "exit"], "", [], [])
    assert_in_out_err([env, "-W:deprecated", "-e", "exit"], "", [],
                       /The environment variable RUBY_GC_HEAP_INIT_SLOTS is deprecated; use environment variables RUBY_GC_HEAP_%d_INIT_SLOTS instead/)

    env = {}
    GC.stat_heap.keys.each do |heap|
      env["RUBY_GC_HEAP_#{heap}_INIT_SLOTS"] = "200000"
    end
    assert_normal_exit("exit", "", :child_env => env)

    env = {}
    GC.stat_heap.keys.each do |heap|
      env["RUBY_GC_HEAP_#{heap}_INIT_SLOTS"] = "0"
    end
    assert_normal_exit("exit", "", :child_env => env)

    env = {
      "RUBY_GC_HEAP_GROWTH_FACTOR" => "2.0",
      "RUBY_GC_HEAP_GROWTH_MAX_SLOTS" => "10000"
    }
    assert_normal_exit("exit", "", :child_env => env)
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_GROWTH_FACTOR=2.0/, "")
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_GROWTH_MAX_SLOTS=10000/, "[ruby-core:57928]")

    if use_rgengc?
      env = {
        "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "0.4",
      }
      # always full GC when RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR < 1.0
      assert_in_out_err([env, "-e", "GC.start; 1000_000.times{Object.new}; p(GC.stat[:minor_gc_count] < GC.stat[:major_gc_count])"], "", ['true'], //, "")
    end

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

    ["0.01", "0.1", "1.0"].each do |i|
      env = {"RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "0", "RUBY_GC_HEAP_REMEMBERED_WB_UNPROTECTED_OBJECTS_LIMIT_RATIO" => i}
      assert_separately([env, "-W0"], __FILE__, __LINE__, <<~RUBY)
        GC.disable
        GC.start
        assert_equal((GC.stat[:old_objects] * #{i}).to_i, GC.stat[:remembered_wb_unprotected_objects_limit])
      RUBY
    end
  end

  def test_gc_parameter_init_slots
    assert_separately([], __FILE__, __LINE__, <<~RUBY)
      # Constant from gc.c.
      GC_HEAP_INIT_SLOTS = 10_000
      GC.stat_heap.each do |_, s|
        multiple = s[:slot_size] / (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD])
        # Allocatable pages are assumed to have lost 1 slot due to alignment.
        slots_per_page = (GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT] / multiple) - 1

        total_slots = s[:heap_eden_slots] + s[:heap_allocatable_pages] * slots_per_page
        assert_operator(total_slots, :>=, GC_HEAP_INIT_SLOTS, s)
      end
    RUBY

    env = {}
    # Make the heap big enough to ensure the heap never needs to grow.
    sizes = GC.stat_heap.keys.reverse.map { |i| (i + 1) * 100_000 }
    GC.stat_heap.keys.each do |heap|
      env["RUBY_GC_HEAP_#{heap}_INIT_SLOTS"] = sizes[heap].to_s
    end
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~RUBY)
      SIZES = #{sizes}
      GC.stat_heap.each do |i, s|
        multiple = s[:slot_size] / (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD])
        # Allocatable pages are assumed to have lost 1 slot due to alignment.
        slots_per_page = (GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT] / multiple) - 1

        total_slots = s[:heap_eden_slots] + s[:heap_allocatable_pages] * slots_per_page

        # The delta is calculated as follows:
        #  - For allocated pages, each page can vary by 1 slot due to alignment.
        #  - For allocatable pages, we can end up with at most 1 extra page of slots.
        assert_in_delta(SIZES[i], total_slots, s[:heap_eden_pages] + slots_per_page, s)
      end
    RUBY

    # Check that the configured sizes are "remembered" across GC invocations.
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~RUBY)
      SIZES = #{sizes}

      # Fill size pool 0 with transient objects.
      ary = []
      while GC.stat_heap(0, :heap_allocatable_pages) != 0
        ary << Object.new
      end
      ary.clear
      ary = nil

      # Clear all the objects that were allocated.
      GC.start

      # Check that we still have the same number of slots as initially configured.
      GC.stat_heap.each do |i, s|
        multiple = s[:slot_size] / (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD])
        # Allocatable pages are assumed to have lost 1 slot due to alignment.
        slots_per_page = (GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT] / multiple) - 1

        total_slots = s[:heap_eden_slots] + s[:heap_allocatable_pages] * slots_per_page

        # The delta is calculated as follows:
        #  - For allocated pages, each page can vary by 1 slot due to alignment.
        #  - For allocatable pages, we can end up with at most 1 extra page of slots.
        assert_in_delta(SIZES[i], total_slots, s[:heap_eden_pages] + slots_per_page, s)
      end
    RUBY

    # Check that we don't grow the heap in minor GC if we have alloctable pages.
    env["RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO"] = "0.3"
    env["RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO"] = "0.99"
    env["RUBY_GC_HEAP_FREE_SLOTS_MAX_RATIO"] = "1.0"
    env["RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR"] = "100" # Large value to disable major GC
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~RUBY)
      SIZES = #{sizes}

      # Run a major GC to clear out dead objects.
      GC.start

      # Disable GC so we can control when GC is ran.
      GC.disable

      # Run minor GC enough times so that we don't grow the heap because we
      # haven't yet ran RVALUE_OLD_AGE minor GC cycles.
      GC::INTERNAL_CONSTANTS[:RVALUE_OLD_AGE].times { GC.start(full_mark: false) }

      # Fill size pool 0 to over 50% full so that the number of allocatable
      # pages that will be created will be over the number in heap_allocatable_pages
      # (calculated using RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO).
      # 70% was chosen here to guarantee that.
      ary = []
      while GC.stat_heap(0, :heap_allocatable_pages) >
          (GC.stat_heap(0, :heap_allocatable_pages) + GC.stat_heap(0, :heap_eden_pages)) * 0.3
        ary << Object.new
      end

      GC.start(full_mark: false)

      # Check that we still have the same number of slots as initially configured.
      GC.stat_heap.each do |i, s|
        multiple = s[:slot_size] / (GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] + GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD])
        # Allocatable pages are assumed to have lost 1 slot due to alignment.
        slots_per_page = (GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT] / multiple) - 1

        total_slots = s[:heap_eden_slots] + s[:heap_allocatable_pages] * slots_per_page

        # The delta is calculated as follows:
        #  - For allocated pages, each page can vary by 1 slot due to alignment.
        #  - For allocatable pages, we can end up with at most 1 extra page of slots.
        assert_in_delta(SIZES[i], total_slots, s[:heap_eden_pages] + slots_per_page, s)
      end
    RUBY
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
    omit "for now"
    assert_separately([], __FILE__, __LINE__, <<-'RUBY', timeout: 30)
      GC::Profiler.enable

      GC.start
      assert_equal(1, GC::Profiler.raw_data.size)
      GC::Profiler.clear
      assert_equal(0, GC::Profiler.raw_data.size)

      200.times{ GC.start }
      assert_equal(200, GC::Profiler.raw_data.size)
      GC::Profiler.clear
      assert_equal(0, GC::Profiler.raw_data.size)
    RUBY
  end

  def test_profiler_raw_data
    GC::Profiler.enable
    GC.start
    assert GC::Profiler.raw_data
  ensure
    GC::Profiler.disable
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
    assert_in_out_err([], <<-EOS, ["\"finalize\""], [], "[ruby-dev:46647]")
      ObjectSpace.define_finalizer(Thread.main) { p 'finalize' }
    EOS
  end

  def test_expand_heap
    assert_separately([], __FILE__, __LINE__, <<~'RUBY')
      GC.start
      base_length = GC.stat[:heap_eden_pages]
      (base_length * 500).times{ 'a' }
      GC.start
      base_length = GC.stat[:heap_eden_pages]
      (base_length * 500).times{ 'a' }
      GC.start
      assert_in_epsilon base_length, (v = GC.stat[:heap_eden_pages]), 1/8r,
            "invalid heap expanding (base_length: #{base_length}, GC.stat[:heap_eden_pages]: #{v})"

      a = []
      (base_length * 500).times{ a << 'a'; nil }
      GC.start
      assert_operator base_length, :<, GC.stat[:heap_eden_pages] + 1
    RUBY
  end

  def test_thrashing_for_young_objects
    # This test prevents bugs like [Bug #18929]

    assert_separately([], __FILE__, __LINE__, <<-'RUBY', timeout: 60)
      # Grow the heap
      @ary = 100_000.times.map { Object.new }

      # Warmup to make sure heap stabilizes
      1_000_000.times { Object.new }

      before_stats = GC.stat
      before_stat_heap = GC.stat_heap

      1_000_000.times { Object.new }

      # Previous loop may have caused GC to be in an intermediate state,
      # running a minor GC here will guarantee that GC will be complete
      GC.start(full_mark: false)

      after_stats = GC.stat
      after_stat_heap = GC.stat_heap

      # Debugging output to for failures in trunk-repeat50@phosphorus-docker
      debug_msg = "before_stats: #{before_stats}\nbefore_stat_heap: #{before_stat_heap}\nafter_stats: #{after_stats}\nafter_stat_heap: #{after_stat_heap}"

      # Should not be thrashing in page creation
      assert_equal before_stats[:heap_allocated_pages], after_stats[:heap_allocated_pages], debug_msg
      assert_equal 0, after_stats[:heap_tomb_pages], debug_msg
      assert_equal 0, after_stats[:total_freed_pages], debug_msg
      # Only young objects, so should not trigger major GC
      assert_equal before_stats[:major_gc_count], after_stats[:major_gc_count], debug_msg
    RUBY
  end

  def test_gc_internals
    assert_not_nil GC::INTERNAL_CONSTANTS[:HEAP_PAGE_OBJ_LIMIT]
    assert_not_nil GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]
  end

  def test_sweep_in_finalizer
    bug9205 = '[ruby-core:58833] [Bug #9205]'
    2.times do
      assert_ruby_status([], <<-'end;', bug9205, timeout: 120)
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

  def test_finalizer_passed_object_id
    assert_in_out_err([], <<~RUBY, ["true"], [])
      o = Object.new
      obj_id = o.object_id
      ObjectSpace.define_finalizer(o, ->(id){ p id == obj_id })
    RUBY
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

  def test_gc_stress_at_startup
    assert_in_out_err([{"RUBY_DEBUG"=>"gc_stress"}], '', [], [], '[Bug #15784]', success: true, timeout: 60)
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

  def test_exception_in_finalizer_procs
    assert_in_out_err(["-W0"], "#{<<~"begin;"}\n#{<<~'end;'}", %w[c1 c2])
    c1 = proc do
      puts "c1"
      raise
    end
    c2 = proc do
      puts "c2"
      raise
    end
    begin;
      tap do
        obj = Object.new
        ObjectSpace.define_finalizer(obj, c1)
        ObjectSpace.define_finalizer(obj, c2)
        obj = nil
      end
    end;
  end

  def test_exception_in_finalizer_method
    assert_in_out_err(["-W0"], "#{<<~"begin;"}\n#{<<~'end;'}", %w[c1 c2])
    def self.c1(x)
      puts "c1"
      raise
    end
    def self.c2(x)
      puts "c2"
      raise
    end
    begin;
      tap do
        obj = Object.new
        ObjectSpace.define_finalizer(obj, method(:c1))
        ObjectSpace.define_finalizer(obj, method(:c2))
        obj = nil
      end
    end;

    assert_normal_exit "#{<<~"begin;"}\n#{<<~'end;'}", '[Bug #20042]'
    begin;
      def (f = Object.new).call = nil # missing ID
      o = Object.new
      ObjectSpace.define_finalizer(o, f)
      o = nil
      GC.start
    end;
  end

  def test_object_ids_never_repeat
    GC.start
    a = 1000.times.map { Object.new.object_id }
    GC.start
    b = 1000.times.map { Object.new.object_id }
    assert_empty(a & b)
  end

  def test_ast_node_buffer
    # https://github.com/ruby/ruby/pull/4416
    Module.new.class_eval( (["# shareable_constant_value: literal"] +
                            (0..100000).map {|i| "M#{ i } = {}" }).join("\n"))
  end

  def test_old_to_young_reference
    original_gc_disabled = GC.disable

    require "objspace"

    old_obj = Object.new
    4.times { GC.start }

    assert_include ObjectSpace.dump(old_obj), '"old":true'

    young_obj = Object.new
    old_obj.instance_variable_set(:@test, young_obj)

    # Not immediately promoted to old generation
    3.times do
      assert_not_include ObjectSpace.dump(young_obj), '"old":true'
      GC.start
    end

    # Takes 4 GC to promote to old generation
    GC.start
    assert_include ObjectSpace.dump(young_obj), '"old":true'
  ensure
    GC.enable if !original_gc_disabled
  end
end
