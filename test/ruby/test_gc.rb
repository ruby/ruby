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
    EnvUtil.without_gc do
      GC.enable
      assert_equal(false, GC.enable)
      assert_equal(false, GC.disable)
      assert_equal(true, GC.disable)
      assert_equal(true, GC.disable)
      assert_nil(GC.start)
      assert_equal(true, GC.enable)
      assert_equal(false, GC.enable)
    end
  end

  def test_gc_config_full_mark_by_default
    config = GC.config
    assert_not_empty(config)
    assert_true(config[:rgengc_allow_full_mark])
  end

  def test_gc_config_invalid_args
    assert_raise(ArgumentError) { GC.config(0) }
  end

  def test_gc_config_setting_returns_updated_config_hash
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

  def test_gc_config_setting_returns_config_hash
    hash = GC.config(no_such_key: true)
    assert_equal(GC.config, hash)
  end

  def test_gc_config_disable_major
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
    GC.config(full_mark: false)

    major_count = GC.stat[:major_gc_count]
    GC.start(global: false)

    assert_operator(major_count, :<, GC.stat[:major_gc_count])
  ensure
    GC.config(full_mark: true)
    GC.start
  end

  def test_gc_config_implementation
    omit unless /darwin|linux/.match(RUBY_PLATFORM)

    gc_name = (ENV['RUBY_GC_LIBRARY'] || "default")
    assert_equal gc_name, GC.config[:implementation]
  end

  def test_gc_config_implementation_is_readonly
    omit unless /darwin|linux/.match(RUBY_PLATFORM)

    assert_raise(ArgumentError) { GC.config(implementation: "somethingelse") }
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

    # GC.stat and GC.stat(:count) are two separate reads of :count. If a GC
    # runs between them (e.g. triggered by an allocation on another thread),
    # :count changes and the two reads disagree. Disable GC so both reads
    # observe the same :count.
    EnvUtil.without_gc do
      stat = GC.stat
      assert_equal stat[:count], GC.stat(:count)
    end
    assert_raise(ArgumentError){ GC.stat(:invalid) }
  end

  def test_stat_constraints
    omit 'stress' if GC.stress

    stat = GC.stat
    # marking_time + sweeping_time could differ from time by 1 because they're stored in nanoseconds
    assert_in_delta stat[:time], stat[:marking_time] + stat[:sweeping_time], 1
    assert_equal stat[:total_allocated_pages], stat[:heap_allocated_pages] + stat[:total_freed_pages]
    assert_equal stat[:heap_available_slots], stat[:heap_live_slots] + stat[:heap_free_slots] + stat[:heap_final_slots]
    assert_equal stat[:heap_live_slots], stat[:total_allocated_objects] - stat[:total_freed_objects] - stat[:heap_final_slots]
    assert_equal stat[:heap_allocated_pages], stat[:heap_eden_pages] + stat[:heap_empty_pages]

    if use_rgengc?
      assert_equal stat[:count], stat[:major_gc_count] + stat[:minor_gc_count] + stat.fetch(:global_gc_count, 0)
    end
  end

  def test_transient_malloc_does_not_trigger_oldmalloc_major_gc
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    env = {
      "RUBY_GC_MALLOC_LIMIT" => "4194304",
      "RUBY_GC_MALLOC_LIMIT_MAX" => "4194304",
      "RUBY_GC_OLDMALLOC_LIMIT" => "1048576",
      "RUBY_GC_OLDMALLOC_LIMIT_MAX" => "1048576",
      "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "1000",
    }
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      GC.start
      GC::Profiler.enable
      40.times do
        500.times { "x" * 4096 }
        GC.start(full_mark: false)
      end
      profile = GC::Profiler.raw_data
      GC::Profiler.disable

      oldmalloc_majors = profile.count { |row| row[:GC_FLAGS][:major_by] == :oldmalloc }
      assert_equal 0, oldmalloc_majors
    RUBY
  end

  def test_lazy_sweep_malloc_does_not_trigger_oldmalloc_major_gc
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    env = {
      "RUBY_GC_MALLOC_LIMIT" => "4194304",
      "RUBY_GC_MALLOC_LIMIT_MAX" => "4194304",
      "RUBY_GC_OLDMALLOC_LIMIT" => "4194304",
      "RUBY_GC_OLDMALLOC_LIMIT_MAX" => "4194304",
      "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "1000",
    }
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      sparse = Array.new(100_000) { "y" * 10 }
      sparse.each_index { |index| sparse[index] = nil if index.odd? }
      GC.start
      GC::Profiler.enable
      20.times do
        GC.start(full_mark: false, immediate_sweep: false)
        10.times { "x" * (512 * 1024) }
      end
      GC.start(full_mark: false)
      profile = GC::Profiler.raw_data
      GC::Profiler.disable

      oldmalloc_majors = profile.count { |row| row[:GC_FLAGS][:major_by] == :oldmalloc }
      assert_equal 100_000, sparse.length
      assert_equal 0, oldmalloc_majors
    RUBY
  end

  def test_retained_malloc_triggers_oldmalloc_major_gc
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    env = {
      "RUBY_GC_OLDMALLOC_LIMIT" => "1048576",
      "RUBY_GC_OLDMALLOC_LIMIT_MAX" => "1048576",
      "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "1000",
    }
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      # Allocate in a dead thread so no stale stack slot keeps the garbage alive past GC.start.
      Thread.new { Array.new(4_000) { "x" * 4096 }; nil }.join
      GC.start
      GC::Profiler.enable
      live = Array.new(1_000) { "x" * 4096 }
      2.times { GC.start(full_mark: false) }
      profile = GC::Profiler.raw_data
      GC::Profiler.disable

      assert_equal 1_000, live.length
      assert_equal :oldmalloc, profile.last[:GC_FLAGS][:major_by], profile.map { |row| row[:GC_FLAGS][:major_by] }.inspect
    RUBY
  end

  def test_retained_malloc_triggers_oldmalloc_major_gc_despite_lazy_sweep_churn
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    env = {
      "RUBY_GC_OLDMALLOC_LIMIT" => "1048576",
      "RUBY_GC_OLDMALLOC_LIMIT_MAX" => "1048576",
      "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "1000",
    }
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      sparse = Array.new(100_000) { "y" * 10 }
      sparse.each_index { |index| sparse[index] = nil if index.odd? }
      GC.start
      GC::Profiler.enable
      live = Array.new(1_000) { "x" * 4096 }
      20.times do
        GC.start(full_mark: false, immediate_sweep: false)
        8.times { ("x" * (1 << 20)).clear }
      end
      GC.start(full_mark: false)
      profile = GC::Profiler.raw_data
      GC::Profiler.disable

      oldmalloc_majors = profile.count { |row| row[:GC_FLAGS][:major_by] == :oldmalloc }
      assert_equal 1_000, live.length
      assert_equal 100_000, sparse.length
      assert_equal 1, oldmalloc_majors
    RUBY
  end

  def test_major_sweep_does_not_create_oldmalloc_debt
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    env = {
      "RUBY_GC_MALLOC_LIMIT" => "1048576",
      "RUBY_GC_MALLOC_LIMIT_MAX" => "1048576",
      "RUBY_GC_OLDMALLOC_LIMIT" => "1048576",
      "RUBY_GC_OLDMALLOC_LIMIT_MAX" => "1048576",
      "RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR" => "1000",
    }
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      buffer_count = 1_024
      buffer_size = 4096
      ring = Array.new(buffer_count) { "x" * buffer_size }
      GC::INTERNAL_CONSTANTS[:RVALUE_OLD_AGE].times { GC.start }
      last_major = GC.stat(:major_gc_count)
      last_iteration = 0
      intervals = []
      reasons = []
      iteration = 0

      while intervals.length < 5
        ring[iteration % buffer_count] = "x" * buffer_size
        iteration += 1
        major = GC.stat(:major_gc_count)
        next if major == last_major

        intervals << (iteration - last_iteration) * buffer_size
        reasons << GC.latest_gc_info(:major_by)
        last_iteration = iteration
        last_major = major
      end

      assert_equal [:oldmalloc] * intervals.length, reasons
      assert_operator intervals.drop(1).max, :<=, 4 * 1024 * 1024, intervals.inspect
    RUBY
  end

  def test_stat_heap
    omit 'stress' if GC.stress

    stat_heap = {}
    stat = {}
    # Initialize to prevent GC in future calls
    GC.stat_heap(0, stat_heap)
    GC.stat(stat)

    GC::INTERNAL_CONSTANTS[:HEAP_COUNT].times do |i|
      EnvUtil.without_gc do
        GC.stat_heap(i, stat_heap)
        GC.stat(stat)
      end

      assert_equal GC.stat_heap(i, :slot_size), stat_heap[:slot_size]
      assert_operator stat_heap[:heap_live_slots], :<=, stat[:heap_live_slots]
      assert_operator stat_heap[:heap_free_slots], :<=, stat[:heap_free_slots]
      assert_operator stat_heap[:heap_final_slots], :<=, stat[:heap_final_slots]
      assert_operator stat_heap[:heap_eden_pages], :<=, stat[:heap_eden_pages]
      assert_operator stat_heap[:heap_eden_slots], :>=, 0
      assert_operator stat_heap[:total_allocated_pages], :>=, 0
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
    assert_raise(ArgumentError) { GC.stat_heap(GC::INTERNAL_CONSTANTS[:HEAP_COUNT]) }
  end

  def test_stat_heap_all
    stat_heap_all = {}
    stat_heap = {}
    # Initialize to prevent GC in future calls
    GC.stat_heap(0, stat_heap)
    GC.stat_heap(nil, stat_heap_all)

    GC::INTERNAL_CONSTANTS[:HEAP_COUNT].times do |i|
      GC.stat_heap(nil, stat_heap_all)
      GC.stat_heap(i, stat_heap)

      # Remove keys that can vary between invocations
      %i(total_allocated_objects heap_live_slots heap_free_slots).each do |sym|
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

    assert_equal stat[:heap_live_slots], stat_heap_sum[:heap_live_slots]
    assert_equal stat[:heap_free_slots], stat_heap_sum[:heap_free_slots]
    assert_equal stat[:heap_final_slots], stat_heap_sum[:heap_final_slots]
    assert_equal stat[:heap_eden_pages], stat_heap_sum[:heap_eden_pages]
    assert_equal stat[:heap_available_slots], stat_heap_sum[:heap_eden_slots]
    assert_equal stat[:total_allocated_objects], stat_heap_sum[:total_allocated_objects]
    assert_equal stat[:total_freed_objects], stat_heap_sum[:total_freed_objects]
  rescue Test::Unit::AssertionFailedError
    # GC.stat and GC.stat_heap are separate reads of the same counters, so
    # anything allocated between them makes the two disagree.  An accounting
    # bug disagrees on the retry too.
    raise if @retried
    @retried = true
    retry
  end

  def test_page_pool_stat_consistency
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    # Freeing arenas back to the OS must keep page_pool_discarded_pages in range.
    # An underflowed counter wraps to a huge value.
    assert_separately([], __FILE__, __LINE__, <<~RUBY, timeout: 60)
      3.times do
        ary = 200_000.times.map { "x" * 40 }
        ary.clear
        GC.start(full_mark: true, immediate_sweep: true)
        GC.start(full_mark: true, immediate_sweep: true)
      end

      stat = GC.stat(process: true)
      assert_operator stat[:page_pool_discarded_pages], :<=, stat[:page_pool_total_pages]
      assert_operator stat[:page_pool_arenas], :>=, 0 # arenas is always 0 if doesn't have mmap
    RUBY
  end

  def test_measure_total_time
    assert_separately([], __FILE__, __LINE__, <<~RUBY, timeout: 60)
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

    assert_separately([{"RUBY_GC_HEAP_INIT_BYTES" => "409600"}, "-W0"], __FILE__, __LINE__, <<-'RUBY')
      GC.start
      count = GC.stat(:heap_free_slots) + GC.stat_heap(0, :heap_allocatable_slots)
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

    EnvUtil.without_gc do
      # allocate objects until need_major_by is set or major GC happens
      objects = []
      while GC.latest_gc_info(:need_major_by).nil?
        objects.append(100.times.map { '*' })
        GC.start(full_mark: false)
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
  end

  def test_latest_gc_info_weak_references_count
    assert_separately([], __FILE__, __LINE__, <<~RUBY)
      GC.disable
      COUNT = 10_000
      # Some weak references may be created, so allow some margin of error
      error_tolerance = 100

      # Run full GC to collect stats about weak references
      GC.start

      before_weak_references_count = GC.latest_gc_info(:weak_references_count)

      # Create some WeakMaps
      ary = Array.new(COUNT)
      COUNT.times.with_index do |i|
        ary[i] = ObjectSpace::WeakMap.new
      end

      # Run full GC to collect stats about weak references
      GC.start

      assert_operator(GC.latest_gc_info(:weak_references_count), :>=, before_weak_references_count + COUNT - error_tolerance)

      before_weak_references_count = GC.latest_gc_info(:weak_references_count)

      # Clear ary, so if ary itself is somewhere on the stack, it won't hold all references
      ary.clear
      ary = nil

      # Free ary, which should GC all the WeakMaps
      GC.start

      assert_operator(GC.latest_gc_info(:weak_references_count), :<=, before_weak_references_count - COUNT + error_tolerance)
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
    assert_in_out_err([], <<-EOS, [], [], "[ruby-dev:44436]", timeout: 30)
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
    env = { "RUBY_GC_HEAP_INIT_BYTES" => "#{200000 * 40}" }
    assert_normal_exit("exit", "", :child_env => env)

    env = { "RUBY_GC_HEAP_INIT_BYTES" => "0" }
    assert_normal_exit("exit", "", :child_env => env)

    env = {
      "RUBY_GC_HEAP_GROWTH_FACTOR" => "2.0",
      "RUBY_GC_HEAP_GROWTH_MAX_BYTES" => "409600"
    }
    assert_normal_exit("exit", "", :child_env => env)
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_GROWTH_FACTOR=2.0/, "")
    assert_in_out_err([env, "-w", "-e", "exit"], "", [], /RUBY_GC_HEAP_GROWTH_MAX_BYTES=409600/, "[ruby-core:57928]")

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

  def test_gc_parameter_init_bytes
    omit "[Bug #21203] This test is flaky and intermittently failing now"

    assert_separately([], __FILE__, __LINE__, <<~RUBY, timeout: 60)
      GC_HEAP_INIT_BYTES = 2560 * 1024

      gc_count = GC.stat(:count)
      # Fill up all heaps to the byte-derived init slot count
      GC::INTERNAL_CONSTANTS[:HEAP_COUNT].times do |i|
        slot_size = GC.stat_heap(i, :slot_size)
        init_slots = GC_HEAP_INIT_BYTES / slot_size
        capa = (slot_size - GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD] - (2 * RbConfig::SIZEOF["void*"])) / RbConfig::SIZEOF["void*"]
        while GC.stat_heap(i, :heap_eden_slots) < init_slots
          Array.new(capa)
        end
      end

      assert_equal gc_count, GC.stat(:count)
    RUBY

    env = { "RUBY_GC_HEAP_INIT_BYTES" => "#{800 * 1024}" }
    assert_separately([env, "-W0"], __FILE__, __LINE__, <<~RUBY, timeout: 60)
      GC_HEAP_INIT_BYTES = 800 * 1024

      gc_count = GC.stat(:count)
      # Fill up all heaps to the byte-derived init slot count
      GC::INTERNAL_CONSTANTS[:HEAP_COUNT].times do |i|
        slot_size = GC.stat_heap(i, :slot_size)
        init_slots = GC_HEAP_INIT_BYTES / slot_size
        capa = (slot_size - GC::INTERNAL_CONSTANTS[:RVALUE_OVERHEAD] - (2 * RbConfig::SIZEOF["void*"])) / RbConfig::SIZEOF["void*"]
        while GC.stat_heap(i, :heap_eden_slots) < init_slots
          Array.new(capa)
        end
      end

      assert_equal gc_count, GC.stat(:count)
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

  def test_profiler_raw_data_limit
    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 30)
      GC::Profiler.configure(max_records: 2)
      GC::Profiler.enable
      GC::Profiler.clear

      3.times { GC.start }
      records = GC::Profiler.raw_data

      assert_equal 2, records.size
      assert_operator records[0][:GC_SEQUENCE], :<, records[1][:GC_SEQUENCE]
      assert_equal records, GC::Profiler.raw_data(limit: 100)
      assert_equal [records.last], GC::Profiler.raw_data(limit: 1)
    RUBY
  end

  def test_profiler_raw_data_since
    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 30)
      GC::Profiler.configure(max_records: 4)
      GC::Profiler.enable
      GC::Profiler.clear

      GC.start
      sequence = GC::Profiler.raw_data.last[:GC_SEQUENCE]
      2.times { GC.start }
      records = GC::Profiler.raw_data(since: sequence)

      assert_equal 2, records.size
      assert_operator records[0][:GC_SEQUENCE], :>, sequence
      assert_operator records[0][:GC_SEQUENCE], :<, records[1][:GC_SEQUENCE]
    RUBY
  end

  def test_profiler_raw_data_with_another_ractor
    # A second objspace sends GC.start through the global collector, which has to record
    # a profile entry the same way a local collection does.
    assert_separately([], <<~RUBY)
      Warning[:experimental] = false
      Ractor.new {}.value

      GC::Profiler.enable
      GC::Profiler.clear
      GC.start

      record = GC::Profiler.raw_data.last
      assert_not_nil record
      assert_kind_of Float, record[:GC_WALL_TIME]

      # A global collection stops the world for its whole duration, so its pause time is
      # recorded like a local one's -- and the phases it measures fit inside it.
      assert_operator record[:GC_PAUSE_TIME], :>, 0.0
      assert_operator record[:GC_MARK_WALL_TIME], :>, 0.0
      assert_operator record[:GC_SWEEP_WALL_TIME], :>, 0.0
      assert_in_delta record[:GC_PAUSE_TIME], record[:GC_STOP_TIME] + record[:GC_STW_TIME], 0.001
      assert_operator record[:GC_MARK_WALL_TIME] + record[:GC_SWEEP_WALL_TIME], :<=, record[:GC_PAUSE_TIME]
    RUBY
  ensure
    GC::Profiler.disable
  end

  def test_profiler_raw_data_includes_wall_time
    auto_compact = GC.auto_compact if GC.respond_to?(:auto_compact)
    GC.auto_compact = false if GC.respond_to?(:auto_compact=)

    GC::Profiler.enable
    GC::Profiler.clear

    GC.start
    record = GC::Profiler.raw_data.last

    assert_kind_of Float, record[:GC_WALL_TIME]
    assert_kind_of Float, record[:GC_INVOKE_WALL_TIME]
    assert_kind_of Float, record[:GC_PAUSE_TIME]
    assert_kind_of Float, record[:GC_STOP_TIME]
    assert_kind_of Float, record[:GC_STW_TIME]
    assert_kind_of Float, record[:GC_MARK_WALL_TIME]
    assert_kind_of Float, record[:GC_SWEEP_WALL_TIME]
    assert_kind_of Float, record[:GC_COMPACT_WALL_TIME]

    assert_operator record[:GC_WALL_TIME], :>=, 0.0
    assert_operator record[:GC_INVOKE_WALL_TIME], :>=, 0.0
    assert_operator record[:GC_PAUSE_TIME], :>=, 0.0
    assert_operator record[:GC_STOP_TIME], :>=, 0.0
    assert_operator record[:GC_STW_TIME], :>=, 0.0
    assert_operator record[:GC_MARK_WALL_TIME], :>=, 0.0
    assert_operator record[:GC_SWEEP_WALL_TIME], :>=, 0.0
    assert_operator record[:GC_COMPACT_WALL_TIME], :>=, 0.0
    assert_in_delta record[:GC_PAUSE_TIME], record[:GC_STOP_TIME] + record[:GC_STW_TIME], 0.001
    assert_operator record[:GC_MARK_WALL_TIME] + record[:GC_SWEEP_WALL_TIME], :<=, record[:GC_PAUSE_TIME] + 0.001
    assert_equal 0.0, record[:GC_COMPACT_WALL_TIME]
  ensure
    GC::Profiler.disable
    GC::Profiler.clear
    GC.auto_compact = auto_compact if GC.respond_to?(:auto_compact=) && defined?(auto_compact)
  end

  def test_profiler_raw_data_reports_compaction_separately_from_sweep_wall_time
    omit "compaction not supported" unless GC.respond_to?(:compact)

    GC::Profiler.enable
    GC::Profiler.clear

    objects = 10_000.times.map { Object.new }
    GC.compact
    record = GC::Profiler.raw_data.last

    assert_kind_of Float, record[:GC_COMPACT_WALL_TIME]
    assert_operator record[:GC_COMPACT_WALL_TIME], :>, 0.0
    phase_wall_time = record[:GC_MARK_WALL_TIME] + record[:GC_SWEEP_WALL_TIME] + record[:GC_COMPACT_WALL_TIME]
    assert_operator phase_wall_time, :<=, record[:GC_PAUSE_TIME] + 0.001
    objects.clear
  rescue NotImplementedError
    omit "compaction not supported"
  ensure
    GC::Profiler.disable
    GC::Profiler.clear
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

      # We need to pre-allocate all the hashes for GC.stat calls, because
      # otherwise the call to GC.stat/GC.stat_heap itself could cause a new
      # page to be allocated and the before/after assertions will fail
      before_stats = {}
      after_stats = {}
      # stat_heap needs a hash of hashes for each heap; easiest way to get the
      # right shape for that is just to call stat_heap with no argument
      before_stat_heap = GC.stat_heap
      after_stat_heap = GC.stat_heap

      # Now collect the actual stats
      GC.stat before_stats
      GC.stat_heap nil, before_stat_heap

      1_000_000.times { Object.new }

      # Previous loop may have caused GC to be in an intermediate state,
      # running a minor GC here will guarantee that GC will be complete
      GC.start(full_mark: false)

      GC.stat after_stats
      GC.stat_heap nil, after_stat_heap

      # Debugging output to for failures in trunk-repeat50@phosphorus-docker
      debug_msg = "before_stats: #{before_stats}\nbefore_stat_heap: #{before_stat_heap}\nafter_stats: #{after_stats}\nafter_stat_heap: #{after_stat_heap}"

      # Should not be thrashing in page creation
      assert_in_epsilon before_stats[:heap_allocated_pages], after_stats[:heap_allocated_pages], 0.5, debug_msg
      assert_equal 0, after_stats[:total_freed_pages], debug_msg
    RUBY
  end

  def test_heaps_grow_independently
    # [Bug #21214]

    assert_separately([], __FILE__, __LINE__, <<-'RUBY', timeout: 60)
      COUNT = 1_000_000

      def allocate_small_object = []
      def allocate_large_object = Array.new(10)

      @arys = Array.new(COUNT) do
        # Allocate 10 small transient objects
        10.times { allocate_small_object }
        # Allocate 1 large object that is persistent
        allocate_large_object
      end

      # Running GC here is required to prevent this test from being flaky because
      # the heap for the small transient objects may not have been cleared by the
      # GC causing heap_available_slots to be slightly over 2 * COUNT.
      GC.start

      heap_available_slots = GC.stat(:heap_available_slots)

      assert_operator(heap_available_slots, :<, COUNT * 2, "GC.stat: #{GC.stat}\nGC.stat_heap: #{GC.stat_heap}")
    RUBY
  end

  def test_gc_internals
    assert_not_nil GC::INTERNAL_CONSTANTS[:HEAP_COUNT]
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
    omit 'randomly hangs on many platforms' if ENV.key?('GITHUB_ACTIONS')
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
    out, err, status = assert_in_out_err(["-e", src], "", [], [], bug10595, signal: :SEGV, timeout: 100) do |*result|
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

  def test_gc_stress_on_obj_allocation
    EnvUtil.under_gc_stress do
      count = GC.count
      iters = 100
      iters.times do
        Object.new
      end
      assert_operator(GC.count - count, :>=, iters)
    end
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
    assert_in_out_err([{"RUBY_DEBUG"=>"gc_stress"}], '', [], [], '[Bug #15784]', success: true, timeout: 120)
  end

  def test_gc_disabled_start
    EnvUtil.without_gc do
      c = GC.count
      GC.start
      assert_equal 1, GC.count - c
    end

    EnvUtil.without_gc do
      c = GC.count
      GC.start(immediate_mark: false, immediate_sweep: false)
      10_000.times { Object.new }
      assert_equal 1, GC.count - c
    end
  end

  def test_vm_object
    assert_normal_exit <<-'end', '[Bug #12583]'
      ObjectSpace.each_object{|o| o.singleton_class rescue 0}
      ObjectSpace.each_object{|o| case o when Module then o.instance_methods end}
    end
  end

  def test_exception_in_finalizer_procs
    require '-test-/stack'
    omit 'failing with ASAN' if Thread.asan?
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
    require '-test-/stack'
    omit 'failing with ASAN' if Thread.asan?
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
    EnvUtil.without_gc do
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
    end
  end

  def test_finalizer_not_run_with_vm_lock
    assert_ractor(<<~'RUBY', timeout: 30)
      Thread.new do
        loop do
          Encoding.list.each do |enc|
            enc.names
          end
        end
      end

      o = Object.new
      ObjectSpace.define_finalizer(o, proc do
        sleep 0.5 # finalizer shouldn't be run with VM lock, otherwise this context switch will crash
      end)
      o = nil
      4.times do
        GC.start
      end
    RUBY
  end

  PROCESS_STAT_KEYS = %i[
    count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count
    page_pool_arenas page_pool_arenas_freed page_pool_total_pages page_pool_discarded_pages
  ].freeze

  def test_stat_process_matches_ractor_statistics
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      GC.disable
      local = GC.stat
      process = GC.stat(process: true)
      keys = %i[count minor_gc_count major_gc_count global_gc_count time marking_time sweeping_time]
      assert_equal local.values_at(*keys), process.values_at(*keys)
    RUBY
  end

  def test_stat_process_count_consistency
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    stat = GC.stat(process: true)
    assert_equal stat[:minor_gc_count] + stat[:major_gc_count] + stat[:global_gc_count], stat[:count]
  end

  def test_stat_process_time_rounding
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    stat = GC.stat(process: true)
    assert_include 0..1, stat[:time] - (stat[:marking_time] + stat[:sweeping_time])
  end

  def test_stat_process_no_argument_returns_new_hash
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    stat = GC.stat(process: true)
    assert_kind_of Hash, stat
    assert_not_same stat, GC.stat(process: true)
    assert_equal PROCESS_STAT_KEYS.sort, stat.keys.sort
    assert stat.values.all? { |value| Integer === value }
  end

  def test_stat_process_nil_argument_returns_new_hash
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    stat = GC.stat(nil, process: true)
    assert_kind_of Hash, stat
    assert_not_same stat, GC.stat(process: true)
    assert_equal PROCESS_STAT_KEYS.sort, stat.keys.sort
    assert stat.values.all? { |value| Integer === value }
  end

  def test_stat_process_symbol_argument_returns_selected_value
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      GC.disable
      stat = GC.stat(process: true)
      value = GC.stat(:count, process: true)
      assert_kind_of Integer, value
      assert_equal stat[:count], value
    RUBY
  end

  def test_stat_process_supplied_hash_is_updated_and_preserved
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    buffer = { sentinel: :keep }
    assert_same buffer, GC.stat(buffer, process: true)
    assert_equal :keep, buffer[:sentinel]
    assert_equal PROCESS_STAT_KEYS.sort, (buffer.keys - [:sentinel]).sort
    assert buffer.values_at(*PROCESS_STAT_KEYS).all? { |value| Integer === value }
  end

  def test_stat_process_supplied_hash_overwrites_stale_values
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      GC.disable
      buffer = { count: -1, time: -1, sentinel: :keep }
      assert_same buffer, GC.stat(buffer, process: true)
      assert_equal :keep, buffer[:sentinel]
      assert_equal GC.stat(:count, process: true), buffer[:count]
      assert_equal GC.stat(:time, process: true), buffer[:time]
    RUBY
  end

  def test_stat_process_rejects_non_hash_or_symbol_arguments
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    assert_raise(TypeError) { GC.stat(0, process: true) }
    assert_raise(TypeError) { GC.stat("count", process: true) }
  end

  def test_stat_process_rejects_unknown_keys
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    assert_raise(ArgumentError) { GC.stat(:no_such_key, process: true) }
    assert_raise(ArgumentError) { GC.stat(:"café", process: true) }
  end

  def test_stat_process_rejects_extra_positional_arguments
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    assert_raise(ArgumentError) { GC.stat(:count, :time, process: true) }
  end

  def test_stat_process_rejects_frozen_hash
    omit 'default GC only' unless GC.config[:implementation] == 'default'

    assert_raise(FrozenError) { GC.stat({ sentinel: 1 }.freeze, process: true) }
  end

  def test_stat_process_counts_deferred_collection_once
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      GC.disable
      before = GC.stat(process: true)
      GC.start(full_mark: true, immediate_mark: false, immediate_sweep: false)
      started = GC.stat(process: true)
      assert_equal [1, 1], [started[:count] - before[:count], started[:major_gc_count] - before[:major_gc_count]]

      GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true)
      settled = GC.stat(process: true)
      assert_equal 1, settled[:count] - started[:count]
    RUBY
  end

  def test_stat_process_counts_collection_with_profiler_disabled
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      GC.disable
      GC::Profiler.disable
      before = GC.stat(:count, process: true)
      GC.start
      assert_equal 1, GC.stat(:count, process: true) - before
    RUBY
  end

  def test_stat_process_profiler_enable_preserves_totals
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      counts = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count]
      GC.disable
      GC::Profiler.disable
      GC.start
      before = GC.stat(process: true).slice(*counts)
      GC::Profiler.enable
      assert_equal before, GC.stat(process: true).slice(*counts)
    RUBY
  end

  def test_stat_process_profiler_disable_preserves_totals
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      counts = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count]
      GC.disable
      GC::Profiler.enable
      GC.start
      before = GC.stat(process: true).slice(*counts)
      GC::Profiler.disable
      assert_equal before, GC.stat(process: true).slice(*counts)
    RUBY
  end

  def test_stat_process_profiler_clear_preserves_totals
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      counts = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count]
      GC.disable
      GC::Profiler.enable
      GC.start
      before = GC.stat(process: true).slice(*counts)
      GC::Profiler.clear
      assert_equal before, GC.stat(process: true).slice(*counts)
    RUBY
  end

  def test_stat_process_profiler_configure_preserves_totals
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      counts = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count]
      GC.disable
      GC::Profiler.enable
      3.times { GC.start }
      before = GC.stat(process: true).slice(*counts)
      GC::Profiler.configure(max_records: 2)
      assert_equal before, GC.stat(process: true).slice(*counts)
    RUBY
  end

  def test_stat_process_retains_finished_ractor_history
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      counts = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count]
      GC.disable
      local_before = GC.stat(:count)
      process_before = GC.stat(:count, process: true)
      ready = Ractor::Port.new
      worker = Ractor.new(ready) do |reply|
        GC.disable
        3.times { GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
        control = Ractor::Port.new
        reply << [GC.stat(:count), control]
        control.receive
      end

      worker_count, control = ready.receive
      assert_equal(3, worker_count, "worker count")
      live = GC.stat(:count, process: true)
      assert_equal(3, live - process_before, "live work missing")
      assert_equal(local_before, GC.stat(:count), "worker changed main count")

      monitor = Ractor::Port.new
      worker.monitor(monitor)
      control << :finish
      assert_equal([worker, :exited], monitor.receive, "worker did not exit")
      assert_equal(live + 1, GC.stat(:count, process: true), "history lost on exit")

      global_before = GC.stat(:count, process: true)
      GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
      assert_equal(1, GC.stat(:count, process: true) - global_before, "global count")
      local_after_global = GC.stat(:count)

      snapshot = GC.stat(process: true).slice(*counts)
      assert_equal(:finish, worker.value, "worker result")
      assert_equal(snapshot, GC.stat(process: true).slice(*counts), "absorption changed history")
      assert_equal(local_after_global, GC.stat(:count), "absorption changed main count")
    RUBY
  end

  def test_stat_process_preserves_nested_ractor_history
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      GC.disable
      local_before = GC.stat(:count)
      process_before = GC.stat(:count, process: true)
      ready = Ractor::Port.new
      outer = assert_in_ractor(ready, value: false) do |reply|
        GC.disable
        3.times { GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
        assert_in_ractor do
          GC.disable
          5.times { GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
          assert_equal(5, GC.stat(:count), "inner count")
        end

        reply << :ready
        Ractor.receive
      end

      ready.receive

      assert_equal(9, GC.stat(:count, process: true) - process_before, "nested history missing")
      outer.ractor.send(:finish)
      assert_equal(:finish, outer.value, "outer result")
      assert_equal(10, GC.stat(:count, process: true) - process_before, "nested history changed")
      assert_equal(local_before, GC.stat(:count), "main inherited nested counts")
    RUBY
  end

  def test_stat_process_counts_global_collection_once
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      GC.disable
      ready = Ractor::Port.new
      worker = Ractor.new(ready) do |reply|
        GC.disable
        reply << :ready
        Ractor.receive
      end
      ready.receive

      before = GC.stat(process: true)
      GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
      after = GC.stat(process: true)
      assert_equal 1, after[:count] - before[:count]
      assert_equal before[:major_gc_count], after[:major_gc_count]
      assert_equal 1, after[:global_gc_count] - before[:global_gc_count]
      assert_equal before[:minor_gc_count], after[:minor_gc_count]

      worker.send(:finish)
      assert_equal :finish, worker.value
    RUBY
  end

  def test_stat_process_reads_are_coherent_during_ractor_collection
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      GC.disable
      keys = %i[count minor_gc_count major_gc_count global_gc_count time marking_time sweeping_time]
      start_count = GC.stat(:count, process: true)
      ready = Ractor::Port.new

      worker = Ractor.new(ready) do |reply|
        GC.disable
        control = Ractor::Port.new
        reply << control
        control.receive
        50.times { GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
        :done
      end
      worker_control = ready.receive

      reader = assert_in_ractor(ready, keys, value: false) do |reply, ks|
        control = Ractor::Port.new
        reply << control
        control.receive
        previous = nil
        read = lambda do
          stat = GC.stat(process: true)
          assert_equal(stat[:minor_gc_count] + stat[:major_gc_count] + stat[:global_gc_count], stat[:count], "count invariant")
          assert_include(0..1, stat[:time] - (stat[:marking_time] + stat[:sweeping_time]), "time rounding")
          ks.each { |key| assert_operator stat[key], :>=, previous[key], "decreasing #{key}" if previous }
          previous = stat
        end
        50.times { read.call }
        reply << :halfway
        control.receive
        50.times { read.call }
        previous
      end
      reader_control = ready.receive

      worker_control << :go
      reader_control << :go
      assert_equal(:halfway, ready.receive, "reader did not reach halfway")
      assert_equal :done, worker.value
      reader_control << :continue
      reader_last = reader.value

      final = GC.stat(process: true)
      assert_equal final[:minor_gc_count] + final[:major_gc_count] + final[:global_gc_count], final[:count]
      assert_include 0..1, final[:time] - (final[:marking_time] + final[:sweeping_time])
      assert keys.all? { |key| final[key] >= reader_last[key] }
      assert_operator final[:count] - start_count, :>=, 50
    RUBY
  end

  def test_stat_process_preserves_measured_time_when_measurement_disabled
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress

    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      GC.disable
      GC.measure_total_time = false
      baseline = GC.stat(process: true)
      ready = Ractor::Port.new
      worker = assert_in_ractor(ready, value: false) do |reply|
        GC.disable
        GC.measure_total_time = true
        retained = Array.new(100_000) { Object.new }
        time_before = GC.stat(:time)
        100.times do
          break if GC.stat(:time) - time_before >= 2
          GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
        end
        assert_operator(GC.stat(:time) - time_before, :>=, 2, "measured time not reached")

        GC.measure_total_time = false
        control = Ractor::Port.new
        reply << [GC.stat(:count), GC.stat(:time), GC.stat(:marking_time), GC.stat(:sweeping_time), control]
        control.receive
        3.times { GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true) }
        [GC.stat(:count), GC.stat(:time), GC.stat(:marking_time), GC.stat(:sweeping_time), retained.length]
      end

      worker_count, worker_time, worker_marking, worker_sweeping, control = ready.receive
      before = GC.stat(process: true)
      assert_equal worker_count, before[:count] - baseline[:count]
      assert_operator worker_time, :>=, 2
      assert_include worker_time..worker_time + 1, before[:time] - baseline[:time]

      control << :continue
      after_count, after_time, after_marking, after_sweeping, retained_count = worker.value
      assert_equal [3, 100_000], [after_count - worker_count, retained_count]
      assert_equal [worker_time, worker_marking, worker_sweeping], [after_time, after_marking, after_sweeping]

      after = GC.stat(process: true)
      assert_equal 4, after[:count] - before[:count]
      assert_equal before.values_at(:time, :marking_time, :sweeping_time),
                   after.values_at(:time, :marking_time, :sweeping_time)
    RUBY
  end

  def test_stat_process_fork_inherits_archived_and_live_history
    omit 'fork not supported' unless Process.respond_to?(:fork)
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress
    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      counts = %i[count time marking_time sweeping_time minor_gc_count major_gc_count global_gc_count]
      GC.disable
      process_before = GC.stat(:count, process: true)

      assert_in_ractor do
        GC.disable
        3.times { GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
        assert_equal(3, GC.stat(:count))
      end

      live_ready = Ractor::Port.new
      live = Ractor.new(live_ready) do |r|
        GC.disable
        2.times { GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
        r << GC.stat(:count)
        Ractor.receive
      end
      assert_equal(2, live_ready.receive, "live count")

      snapshot = GC.stat(process: true).slice(*counts)
      assert_equal 6, snapshot[:count] - process_before
      read, write = IO.pipe
      pid = Process.fork do
        read.close
        child_initial = GC.stat(process: true).slice(*counts)
        write.write(Marshal.dump(child_initial))
        GC.start(full_mark: true, immediate_mark: true, immediate_sweep: true)
        child_after = GC.stat(process: true).slice(*counts)
        write.write(Marshal.dump(child_after))
        write.close
        exit!(0)
      end
      write.close
      child_initial = Marshal.load(read)
      child_after = Marshal.load(read)
      read.close
      _, status = Process.waitpid2(pid)
      assert_predicate(status, :success?, "child exit status")
      assert_equal snapshot, child_initial
      assert_equal 1, child_after[:count] - child_initial[:count]
      assert_equal snapshot[:count], GC.stat(:count, process: true)

      live.send(:finish)
      assert_equal :finish, live.value
    RUBY
  end

  def test_stat_process_selects_ractor_or_process_data
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress
    assert_separately([], __FILE__, __LINE__, <<~'RUBY', timeout: 60)
      Warning[:experimental] = false
      GC.disable
      count_keys = %i[count minor_gc_count major_gc_count global_gc_count time marking_time sweeping_time]
      page_pool_keys = %i[page_pool_arenas page_pool_arenas_freed page_pool_total_pages page_pool_discarded_pages]
      process_keys = count_keys + page_pool_keys
      local_gauge = :heap_live_slots

      default = GC.stat
      assert_include default.keys, local_gauge
      assert_include default.keys, :global_gc_invocation_count
      assert_empty default.keys & page_pool_keys
      page_pool_keys.each do |key|
        assert_raise(ArgumentError) { GC.stat(key) }
      end

      [false, nil].each do |process|
        explicit = GC.stat(process: process)
        assert_not_same default, explicit
        assert_equal default.keys, explicit.keys
        assert_equal default.values_at(*count_keys), explicit.values_at(*count_keys)
        assert_equal default[:count], GC.stat(:count, process: process)
        assert_equal default[:count], GC.stat(nil, process: process)[:count]

        buffer = { process: true, sentinel: :keep, count: -1 }
        assert_same buffer, GC.stat(buffer, process: process)
        assert_equal [true, :keep, default[:count]], buffer.values_at(:process, :sentinel, :count)
        assert_kind_of Integer, buffer[local_gauge]
        assert_raise(FrozenError) { GC.stat({}.freeze, process: process) }
      end

      process = GC.stat(process: true)
      assert_equal process_keys.sort, process.keys.sort
      [local_gauge, :global_gc_invocation_count].each do |key|
        assert_raise(ArgumentError) { GC.stat(key, process: true) }
      end
      assert_equal process[:count], GC.stat(:count, process: true)
      [1, :ractor, "false"].each do |value|
        assert_equal process.keys, GC.stat(process: value).keys
      end

      assert_raise(ArgumentError) { GC.stat(scope: :global) }
      assert_raise(ArgumentError) { GC.stat(foo: :bar) }

      out = { process: false, sentinel: :ok, count: -1 }
      assert_same out, GC.stat(out, process: true)
      assert_equal [false, :ok], out.values_at(:process, :sentinel)
      assert_equal process_keys.sort, (out.keys - [:process, :sentinel]).sort
      assert_equal GC.stat(:count, process: true), out[:count]

      assert_raise(FrozenError) { GC.stat({}.freeze, process: true) }
    RUBY
  end

  def test_stat_process_is_unsupported_by_non_default_gc
    omit 'skipped on default GC' if GC.config[:implementation] == 'default'

    assert_kind_of Hash, GC.stat
    assert_kind_of Integer, GC.stat(:count)
    assert_kind_of Hash, GC.stat(process: false)
    assert_kind_of Integer, GC.stat(:count, process: false)
    assert_raise(NotImplementedError) { GC.stat(process: true) }
    assert_raise(NotImplementedError) { GC.stat(:count, process: true) }
    assert_raise(NotImplementedError) { GC.stat({}, process: true) }
  end

  def test_gc_start_ractor_global_false
    omit "no GC.stat(:global_gc_count)" unless GC.stat.key?(:global_gc_count)
    assert_ractor(<<~'RUBY')
      r = Ractor.new { Ractor.receive }
      before = GC.stat(:global_gc_count)
      GC.start(global: false)
      after = GC.stat(:global_gc_count)
      assert_equal 0, after - before
      r.send(:done)
    RUBY
  end

  def test_gc_start_ractor_global_true
    omit "no GC.stat(:global_gc_count)" unless GC.stat.key?(:global_gc_count)
    assert_ractor(<<~'RUBY')
      r = Ractor.new { Ractor.receive }
      [{global: true}, {}].each do |opts|
        before = GC.stat(:global_gc_count)
        GC.start(**opts)
        after = GC.stat(:global_gc_count)
        assert_operator after - before, :>=, 1
      end
      r.send(:done)
    RUBY
  end

  def test_stat_global_gc_counts_in_driver
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY')
      r = Ractor.new { Ractor.receive }
      GC.disable
      before = GC.stat
      GC.start(global: true)
      after = GC.stat
      assert_equal 1, after[:global_gc_count] - before[:global_gc_count]
      assert_equal 1, after[:global_gc_invocation_count] - before[:global_gc_invocation_count]
      assert_equal 1, after[:count] - before[:count]
      assert_equal before[:major_gc_count], after[:major_gc_count]

      GC.start(global: false)
      local = GC.stat
      global_keys = %i[global_gc_count global_gc_invocation_count]
      assert_equal after.values_at(*global_keys), local.values_at(*global_keys)
      assert_equal 1, local[:major_gc_count] - after[:major_gc_count]
      r.send(:done)
    RUBY
  end

  def test_stat_global_gc_count_includes_collections_started_by_other_ractors
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY')
      ready = Ractor::Port.new
      worker = Ractor.new(ready) do |port|
        port << :ready
        Ractor.receive
        before = GC.stat(:global_gc_invocation_count)
        GC.start(global: true)
        GC.stat(:global_gc_invocation_count) - before
      end
      ready.receive
      GC.disable
      main_before = GC.stat
      worker << :go
      assert_operator worker.value, :>=, 1
      main_after = GC.stat

      collected = main_after[:global_gc_count] - main_before[:global_gc_count]
      assert_operator collected, :>=, 1
      assert_equal collected, main_after[:count] - main_before[:count]
      assert_equal main_before[:global_gc_invocation_count], main_after[:global_gc_invocation_count]
    RUBY
  end

  def test_stat_process_global_gc_count_sums_invocation_counts
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY')
      worker = Ractor.new do
        Ractor.receive
        GC.start(global: true)
        GC.stat(:global_gc_invocation_count)
      end

      GC.disable
      before = GC.stat(process: true)
      assert_equal GC.stat(:global_gc_invocation_count), before[:global_gc_count]

      worker << :go
      worker_count = worker.value
      assert_operator worker_count, :>=, 1

      after = GC.stat(process: true)
      assert_equal GC.stat(:global_gc_invocation_count) + worker_count, after[:global_gc_count]
    RUBY
  end

  def test_stat_process_global_gc_count_retains_unjoined_ractor
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    assert_ractor(<<~'RUBY')
      done = Ractor::Port.new
      Ractor.new(done) do |reply|
        GC.start(global: true)
        reply << GC.stat(:global_gc_invocation_count)
      end
      worker_count = done.receive
      assert_operator worker_count, :>=, 1
      Thread.pass until Ractor.count == 1

      GC.disable
      after = GC.stat(process: true)
      assert_equal GC.stat(:global_gc_invocation_count) + worker_count, after[:global_gc_count]
    RUBY
  end

  def test_stat_heap_marked_slots_counts_own_heap_after_global_gc
    omit 'default GC only' unless GC.config[:implementation] == 'default'
    omit 'stress' if GC.stress
    assert_ractor(<<~'RUBY')
      ready = Ractor::Port.new
      worker = Ractor.new(ready) do |port|
        GC.disable
        retained = Array.new(200_000) { Object.new }
        port << :ready
        Ractor.receive
        [GC.stat(:heap_marked_slots), retained.size]
      end
      ready.receive

      GC.disable
      GC.start(global: true)
      main = GC.stat
      assert_operator main[:heap_marked_slots], :<=, main[:heap_available_slots]

      worker << :go
      worker_marked, retained = worker.value
      assert_operator worker_marked, :>=, retained
    RUBY
  end
end
