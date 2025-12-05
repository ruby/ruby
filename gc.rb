# for gc.c

#  The \GC module provides an interface to Ruby's mark-and-sweep garbage collection mechanism.
#
#  Some of the underlying methods are also available via the ObjectSpace module.
#
#  You may obtain information about the operation of the \GC through GC::Profiler.
module GC

  # Initiates garbage collection, even if explicitly disabled by GC.disable.
  #
  # Keyword arguments:
  #
  # - +full_mark+:
  #   its boolean value determines whether to perform a major garbage collection cycle:
  #
  #   - +true+: initiates a major garbage collection cycle,
  #     meaning all objects (old and new) are marked.
  #   - +false+: initiates a minor garbage collection cycle,
  #     meaning only young objects are marked.
  #
  # - +immediate_mark+:
  #   its boolean value determines whether to perform incremental marking:
  #
  #   - +true+: marking is completed before the method returns.
  #   - +false+: marking is performed by parts,
  #     interleaved with program execution both before the method returns and afterward;
  #     therefore marking may not be completed before the return.
  #     Note that if +full_mark+ is +false+, marking will always be immediate,
  #     regardless of the value of +immediate_mark+.
  #
  # - +immediate_sweep+:
  #   its boolean value determines whether to defer sweeping (using lazy sweep):
  #
  #   - +true+: sweeping is completed before the method returns.
  #   - +false+: sweeping is performed by parts,
  #     interleaved with program execution both before the method returns and afterward;
  #     therefore sweeping may not be completed before the return.
  #
  # Note that these keyword arguments are implementation- and version-dependent,
  # are not guaranteed to be future-compatible,
  # and may be ignored in some implementations.
  def self.start full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  # Alias of GC.start
  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  # call-seq:
  #   GC.enable -> true or false
  #
  # Enables garbage collection;
  # returns whether garbage collection was disabled:
  #
  #   GC.disable
  #   GC.enable # => true
  #   GC.enable # => false
  #
  def self.enable
    Primitive.gc_enable
  end

  # call-seq:
  #    GC.disable -> true or false
  #
  # Disables garbage collection (but GC.start remains potent):
  # returns whether garbage collection was already disabled.
  #
  #   GC.enable
  #   GC.disable # => false
  #   GC.disable # => true
  #
  def self.disable
    Primitive.gc_disable
  end

  # call-seq:
  #   GC.stress -> setting
  #
  # Returns the current \GC stress-mode setting,
  # which initially is +false+.
  #
  # The stress mode may be set by method GC.stress=.
  def self.stress
    Primitive.gc_stress_get
  end

  # call-seq:
  #   GC.stress = value -> value
  #
  # Enables or disables stress mode;
  # enabling stress mode will degrade performance; it is only for debugging.
  #
  # Sets the current \GC stress mode to the given value:
  #
  # - If the value is +nil+ or +false+, disables stress mode.
  # - If the value is an integer,
  #   enables stress mode with certain flags; see below.
  # - Otherwise, enables stress mode;
  #   \GC is invoked at every \GC opportunity: all memory and object allocations.
  #
  # The flags are bits in the given integer:
  #
  # - +0x01+: No major \GC.
  # - +0x02+: No immediate sweep.
  # - +0x04+: Full mark after malloc/calloc/realloc.
  #
  def self.stress=(flag)
    Primitive.gc_stress_set_m flag
  end

  # call-seq:
  #   self.count -> integer
  #
  # Returns the total number of times garbage collection has occurred:
  #
  #   GC.count # => 385
  #   GC.start
  #   GC.count # => 386
  #
  def self.count
    Primitive.gc_count
  end

  # call-seq:
  #   GC.stat -> new_hash
  #   GC.stat(key) -> value
  #   GC.stat(hash) -> hash
  #
  # This method is implementation-specific to CRuby.
  #
  # Returns \GC statistics.
  # The particular statistics are implementation-specific
  # and may change in the future without notice.
  #
  # With no argument given,
  # returns information about the most recent garbage collection:
  #
  #   GC.stat
  #   # =>
  #   {count: 28,
  #    time: 1,
  #    marking_time: 1,
  #    sweeping_time: 0,
  #    heap_allocated_pages: 521,
  #    heap_empty_pages: 0,
  #    heap_allocatable_slots: 0,
  #    heap_available_slots: 539590,
  #    heap_live_slots: 422243,
  #    heap_free_slots: 117347,
  #    heap_final_slots: 0,
  #    heap_marked_slots: 264877,
  #    heap_eden_pages: 521,
  #    total_allocated_pages: 521,
  #    total_freed_pages: 0,
  #    total_allocated_objects: 2246376,
  #    total_freed_objects: 1824133,
  #    malloc_increase_bytes: 50982,
  #    malloc_increase_bytes_limit: 18535172,
  #    minor_gc_count: 18,
  #    major_gc_count: 10,
  #    compact_count: 0,
  #    read_barrier_faults: 0,
  #    total_moved_objects: 0,
  #    remembered_wb_unprotected_objects: 0,
  #    remembered_wb_unprotected_objects_limit: 2162,
  #    old_objects: 216365,
  #    old_objects_limit: 432540,
  #    oldmalloc_increase_bytes: 1654232,
  #    oldmalloc_increase_bytes_limit: 16846103}
  #
  # With symbol argument +key+ given,
  # returns the value for that key:
  #
  #   GC.stat(:count) # => 30
  #
  # With hash argument +hash+ given,
  # returns that hash with GC statistics merged into its content;
  # this form may be useful in minimizing {probe effects}[https://en.wikipedia.org/wiki/Probe_effect]:
  #
  #   h = {foo: 0, bar: 1}
  #   GC.stat(h)
  #   h.keys.take(5) # => [:foo, :bar, :count, :time, :marking_time]
  #
  # The hash includes entries such as:
  #
  # - +:count+:
  #   The total number of garbage collections run since application start
  #   (count includes both minor and major garbage collections).
  # - +:time+:
  #   The total time spent in garbage collections (in milliseconds).
  # - +:heap_allocated_pages+:
  #   The total number of allocated pages.
  # - +:heap_empty_pages+:
  #   The number of pages with no live objects, and that could be released to the system.
  # - +:heap_sorted_length+:
  #   The number of pages that can fit into the buffer that holds references to  all pages.
  # - +:heap_allocatable_pages+:
  #   The total number of pages the application could allocate without additional \GC.
  # - +:heap_available_slots+:
  #   The total number of slots in all +:heap_allocated_pages+.
  # - +:heap_live_slots+:
  #   The total number of slots which contain live objects.
  # - +:heap_free_slots+:
  #   The total number of slots which do not contain live objects.
  # - +:heap_final_slots+:
  #   The total number of slots with pending finalizers to be run.
  # - +:heap_marked_slots+:
  #   The total number of objects marked in the last \GC.
  # - +:heap_eden_pages+:
  #   The total number of pages which contain at least one live slot.
  # - +:total_allocated_pages+:
  #   The cumulative number of pages allocated since application start.
  # - +:total_freed_pages+:
  #   The cumulative number of pages freed since application start.
  # - +:total_allocated_objects+:
  #   The cumulative number of objects allocated since application start.
  # - +:total_freed_objects+:
  #   The cumulative number of objects freed since application start.
  # - +:malloc_increase_bytes+:
  #   Amount of memory allocated on the heap for objects. Decreased by any \GC.
  # - +:malloc_increase_bytes_limit+:
  #   When +:malloc_increase_bytes+ crosses this limit, \GC is triggered.
  # - +:minor_gc_count+:
  #   The total number of minor garbage collections run since process start.
  # - +:major_gc_count+:
  #   The total number of major garbage collections run since process start.
  # - +:compact_count+:
  #   The total number of compactions run since process start.
  # - +:read_barrier_faults+:
  #   The total number of times the read barrier was triggered during compaction.
  # - +:total_moved_objects+:
  #   The total number of objects compaction has moved.
  # - +:remembered_wb_unprotected_objects+:
  #   The total number of objects without write barriers.
  # - +:remembered_wb_unprotected_objects_limit+:
  #   When +:remembered_wb_unprotected_objects+ crosses this limit, major \GC is triggered.
  # - +:old_objects+:
  #   Number of live, old objects which have survived at least 3 garbage collections.
  # - +:old_objects_limit+:
  #   When +:old_objects+ crosses this limit, major \GC is triggered.
  # - +:oldmalloc_increase_bytes+:
  #   Amount of memory allocated on the heap for objects. Decreased by major \GC.
  # - +:oldmalloc_increase_bytes_limit+:
  #   When +:oldmalloc_increase_bytes+ crosses this limit, major \GC is triggered.
  #
  def self.stat hash_or_key = nil
    Primitive.gc_stat hash_or_key
  end

  # call-seq:
  #    GC.stat_heap -> new_hash
  #    GC.stat_heap(heap_id) -> new_hash
  #    GC.stat_heap(heap_id, key) -> value
  #    GC.stat_heap(nil, hash) -> hash
  #    GC.stat_heap(heap_id, hash) -> hash
  #
  # This method is implementation-specific to CRuby.
  #
  # Returns statistics for \GC heaps.
  # The particular statistics are implementation-specific
  # and may change in the future without notice.
  #
  # With no argument given, returns statistics for all heaps:
  #
  #   GC.stat_heap
  #   # =>
  #   {0 =>
  #     {slot_size: 40,
  #      heap_eden_pages: 246,
  #      heap_eden_slots: 402802,
  #      total_allocated_pages: 246,
  #      force_major_gc_count: 2,
  #      force_incremental_marking_finish_count: 1,
  #      total_allocated_objects: 33867152,
  #      total_freed_objects: 33520523},
  #    1 =>
  #     {slot_size: 80,
  #      heap_eden_pages: 84,
  #      heap_eden_slots: 68746,
  #      total_allocated_pages: 84,
  #      force_major_gc_count: 1,
  #      force_incremental_marking_finish_count: 4,
  #      total_allocated_objects: 147491,
  #      total_freed_objects: 90699},
  #    2 =>
  #     {slot_size: 160,
  #      heap_eden_pages: 157,
  #      heap_eden_slots: 64182,
  #      total_allocated_pages: 157,
  #      force_major_gc_count: 0,
  #      force_incremental_marking_finish_count: 0,
  #      total_allocated_objects: 211460,
  #      total_freed_objects: 190075},
  #    3 =>
  #     {slot_size: 320,
  #      heap_eden_pages: 8,
  #      heap_eden_slots: 1631,
  #      total_allocated_pages: 8,
  #      force_major_gc_count: 0,
  #      force_incremental_marking_finish_count: 0,
  #      total_allocated_objects: 1422,
  #      total_freed_objects: 700},
  #    4 =>
  #     {slot_size: 640,
  #      heap_eden_pages: 16,
  #      heap_eden_slots: 1628,
  #      total_allocated_pages: 16,
  #      force_major_gc_count: 0,
  #      force_incremental_marking_finish_count: 0,
  #      total_allocated_objects: 1230,
  #      total_freed_objects: 309}}
  #
  # In the example above, the keys in the outer hash are the heap identifiers:
  #
  #   GC.stat_heap.keys # => [0, 1, 2, 3, 4]
  #
  # On CRuby, each heap identifier is an integer;
  # on other implementations, a heap identifier may be a string.
  #
  # With only argument +heap_id+ given,
  # returns statistics for the given heap identifier:
  #
  #   GC.stat_heap(2)
  #   # =>
  #   {slot_size: 160,
  #    heap_eden_pages: 157,
  #    heap_eden_slots: 64182,
  #    total_allocated_pages: 157,
  #    force_major_gc_count: 0,
  #    force_incremental_marking_finish_count: 0,
  #    total_allocated_objects: 225018,
  #    total_freed_objects: 206647}
  #
  # With arguments +heap_id+ and +key+ given,
  # returns the value for the given key in the given heap:
  #
  #   GC.stat_heap(2, :slot_size) # => 160
  #
  # With arguments +nil+ and +hash+ given,
  # merges the statistics for all heaps into the given hash:
  #
  #   h = {foo: 0, bar: 1}
  #   GC.stat_heap(nil, h).keys # => [:foo, :bar, 0, 1, 2, 3, 4]
  #
  # With arguments +heap_id+ and +hash+ given,
  # merges the statistics for the given heap into the given hash:
  #
  #   h = {foo: 0, bar: 1}
  #   GC.stat_heap(2, h).keys
  #   # =>
  #   [:foo,
  #    :bar,
  #    :slot_size,
  #    :heap_eden_pages,
  #    :heap_eden_slots,
  #    :total_allocated_pages,
  #    :force_major_gc_count,
  #    :force_incremental_marking_finish_count,
  #    :total_allocated_objects,
  #    :total_freed_objects]
  #
  # The statistics for a heap may include:
  #
  # - +:slot_size+:
  #   The slot size of the heap in bytes.
  # - +:heap_allocatable_pages+:
  #   The number of pages that can be allocated without triggering a new
  #   garbage collection cycle.
  # - +:heap_eden_pages+:
  #   The number of pages in the eden heap.
  # - +:heap_eden_slots+:
  #   The total number of slots in all of the pages in the eden heap.
  # - +:total_allocated_pages+:
  #   The total number of pages that have been allocated in the heap.
  # - +:total_freed_pages+:
  #   The total number of pages that have been freed and released back to the
  #   system in the heap.
  # - +:force_major_gc_count+:
  #   The number of times this heap has forced major garbage collection cycles
  #   to start due to running out of free slots.
  # - +:force_incremental_marking_finish_count+:
  #   The number of times this heap has forced incremental marking to complete
  #   due to running out of pooled slots.
  #
  def self.stat_heap heap_name = nil, hash_or_key = nil
    Primitive.gc_stat_heap heap_name, hash_or_key
  end

  # call-seq:
  #     GC.config -> hash
  #     GC.config(hash_to_merge) -> hash
  #
  # This method is implementation-specific to CRuby.
  #
  # Sets or gets information about the current \GC configuration.
  #
  # Configuration parameters are \GC implementation-specific and may change without notice.
  #
  # With no argument given, returns a hash containing the configuration:
  #
  #   GC.config
  #   # => {rgengc_allow_full_mark: true, implementation: "default"}
  #
  # With argument +hash_to_merge+ given,
  # merges that hash into the stored configuration hash;
  # ignores unknown hash keys;
  # returns the configuration hash:
  #
  #   GC.config(rgengc_allow_full_mark: false)
  #   # => {rgengc_allow_full_mark: false, implementation: "default"}
  #   GC.config(foo: 'bar')
  #   # => {rgengc_allow_full_mark: false, implementation: "default"}
  #
  # <b>All-Implementations Configuration</b>
  #
  # The single read-only entry for all implementations is:
  #
  # - +:implementation+:
  #   the string name of the implementation;
  #   for the Ruby default implementation, <tt>'default'</tt>.
  #
  # <b>Implementation-Specific Configuration</b>
  #
  # A \GC implementation maintains its own implementation-specific configuration.
  #
  # For Ruby's default implementation the single entry is:
  #
  # - +:rgengc_allow_full_mark+:
  #   Controls whether the \GC is allowed to run a full mark (young & old objects):
  #
  #   - +true+ (default): \GC interleaves major and minor collections.
  #     A flag is set to notify GC that a full mark has been requested.
  #     This flag is accessible via GC.latest_gc_info(:need_major_by).
  #   - +false+: \GC does not initiate a full marking cycle unless explicitly directed by user code;
  #     see GC.start.
  #     Setting this parameter to +false+ disables young-to-old promotion.
  #     For performance reasons, we recommended warming up the application using Process.warmup
  #     before setting this parameter to +false+.
  #
  def self.config hash = nil
    if Primitive.cexpr!("RBOOL(RB_TYPE_P(hash, T_HASH))")
      if hash.include?(:implementation)
        raise ArgumentError, 'Attempting to set read-only key "Implementation"'
      end

      Primitive.gc_config_set hash
    elsif hash != nil
      raise ArgumentError
    end

    Primitive.gc_config_get
  end

  # call-seq:
  #   GC.latest_gc_info -> new_hash
  #   GC.latest_gc_info(key) -> value
  #   GC.latest_gc_info(hash) -> hash
  #
  # With no argument given,
  # returns information about the most recent garbage collection:
  #
  #   GC.latest_gc_info
  #   # =>
  #   {major_by: :force,
  #    need_major_by: nil,
  #    gc_by: :method,
  #    have_finalizer: false,
  #    immediate_sweep: true,
  #    state: :none,
  #    weak_references_count: 0,
  #    retained_weak_references_count: 0}
  #
  # With symbol argument +key+ given,
  # returns the value for that key:
  #
  #   GC.latest_gc_info(:gc_by) # => :newobj
  #
  # With hash argument +hash+ given,
  # returns that hash with GC information merged into its content;
  # this form may be useful in minimizing {probe effects}[https://en.wikipedia.org/wiki/Probe_effect]:
  #
  #   h = {foo: 0, bar: 1}
  #   GC.latest_gc_info(h)
  #   # =>
  #   {foo: 0,
  #    bar: 1,
  #    major_by: nil,
  #    need_major_by: nil,
  #    gc_by: :newobj,
  #    have_finalizer: false,
  #    immediate_sweep: false,
  #    state: :sweeping,
  #    weak_references_count: 0,
  #    retained_weak_references_count: 0}
  #
  def self.latest_gc_info hash_or_key = nil
    if hash_or_key == nil
      hash_or_key = {}
    elsif Primitive.cexpr!("RBOOL(!SYMBOL_P(hash_or_key) && !RB_TYPE_P(hash_or_key, T_HASH))")
      raise TypeError, "non-hash or symbol given"
    end

    Primitive.cstmt! %{
      return rb_gc_latest_gc_info(hash_or_key);
    }
  end

  # call-seq:
  #   GC.measure_total_time = setting -> setting
  #
  # Enables or disables \GC total time measurement;
  # returns +setting+.
  # See GC.total_time.
  #
  # When argument +object+ is +nil+ or +false+, disables total time measurement;
  # GC.measure_total_time then returns +false+:
  #
  #   GC.measure_total_time = nil   # => nil
  #   GC.measure_total_time         # => false
  #   GC.measure_total_time = false # => false
  #   GC.measure_total_time         # => false
  #
  # Otherwise, enables total time measurement;
  # GC.measure_total_time then returns +true+:
  #
  #   GC.measure_total_time = true # => true
  #   GC.measure_total_time        # => true
  #   GC.measure_total_time = :foo # => :foo
  #   GC.measure_total_time        # => true
  #
  # Note that when enabled, total time measurement affects performance.
  def self.measure_total_time=(flag)
    Primitive.cstmt! %{
      rb_gc_impl_set_measure_total_time(rb_gc_get_objspace(), flag);
      return flag;
    }
  end

  # call-seq:
  #   GC.measure_total_time -> true or false
  #
  # Returns the setting for \GC total time measurement;
  # the initial setting is +true+.
  # See GC.total_time.
  def self.measure_total_time
    Primitive.cexpr! %{
      RBOOL(rb_gc_impl_get_measure_total_time(rb_gc_get_objspace()))
    }
  end

  # call-seq:
  #    GC.total_time -> integer
  #
  # Returns the \GC total time in nanoseconds:
  #
  #   GC.total_time # => 156250
  #
  # Note that total time accumulates
  # only when total time measurement is enabled
  # (that is, when GC.measure_total_time is +true+):
  #
  #   GC.measure_total_time # => true
  #   GC.total_time # => 625000
  #   GC.start
  #   GC.total_time # => 937500
  #   GC.start
  #   GC.total_time # => 1093750
  #
  #   GC.measure_total_time = false
  #   GC.total_time # => 1250000
  #   GC.start
  #   GC.total_time # => 1250000
  #   GC.start
  #   GC.total_time # => 1250000
  #
  #   GC.measure_total_time = true
  #   GC.total_time # => 1250000
  #   GC.start
  #   GC.total_time # => 1406250
  #
  def self.total_time
    Primitive.cexpr! %{
      ULL2NUM(rb_gc_impl_get_total_time(rb_gc_get_objspace()))
    }
  end
end

module ObjectSpace
  # Alias of GC.start
  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  module_function :garbage_collect
end
