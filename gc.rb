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
  # Note that these keword arguments are implementation- and version-dependent,
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
  #    GC.enable -> true or false
  #
  # Enables garbage collection, returning +true+ if garbage
  # collection was previously disabled.
  #
  #    GC.disable   #=> false
  #    GC.enable    #=> true
  #    GC.enable    #=> false
  #
  def self.enable
    Primitive.gc_enable
  end

  # call-seq:
  #    GC.disable -> true or false
  #
  # Disables garbage collection, returning +true+ if garbage
  # collection was already disabled.
  #
  #    GC.disable   #=> false
  #    GC.disable   #=> true
  def self.disable
    Primitive.gc_disable
  end

  # call-seq:
  #   GC.stress -> integer, true, or false
  #
  # Returns the current status of \GC stress mode.
  def self.stress
    Primitive.gc_stress_get
  end

  # call-seq:
  #   GC.stress = flag -> flag
  #
  # Updates the \GC stress mode.
  #
  # When stress mode is enabled, the \GC is invoked at every \GC opportunity:
  # all memory and object allocations.
  #
  # Enabling stress mode will degrade performance; it is only for debugging.
  #
  # The flag can be true, false, or an integer bitwise-ORed with the following flags:
  #   0x01:: no major GC
  #   0x02:: no immediate sweep
  #   0x04:: full mark after malloc/calloc/realloc
  def self.stress=(flag)
    Primitive.gc_stress_set_m flag
  end

  # call-seq:
  #    GC.count -> Integer
  #
  # Returns the number of times \GC has occurred since the process started.
  def self.count
    Primitive.gc_count
  end

  # call-seq:
  #    GC.stat -> Hash
  #    GC.stat(hash) -> Hash
  #    GC.stat(:key) -> Numeric
  #
  # Returns a Hash containing information about the \GC.
  #
  # The contents of the hash are implementation-specific and may change in
  # the future without notice.
  #
  # The hash includes internal statistics about \GC such as:
  #
  # [count]
  #   The total number of garbage collections run since application start
  #   (count includes both minor and major garbage collections)
  # [time]
  #   The total time spent in garbage collections (in milliseconds)
  # [heap_allocated_pages]
  #   The total number of +:heap_eden_pages+ + +:heap_tomb_pages+
  # [heap_sorted_length]
  #   The number of pages that can fit into the buffer that holds references to
  #   all pages
  # [heap_allocatable_pages]
  #   The total number of pages the application could allocate without additional \GC
  # [heap_available_slots]
  #   The total number of slots in all +:heap_allocated_pages+
  # [heap_live_slots]
  #   The total number of slots which contain live objects
  # [heap_free_slots]
  #   The total number of slots which do not contain live objects
  # [heap_final_slots]
  #   The total number of slots with pending finalizers to be run
  # [heap_marked_slots]
  #   The total number of objects marked in the last \GC
  # [heap_eden_pages]
  #   The total number of pages which contain at least one live slot
  # [heap_tomb_pages]
  #   The total number of pages which do not contain any live slots
  # [total_allocated_pages]
  #   The cumulative number of pages allocated since application start
  # [total_freed_pages]
  #   The cumulative number of pages freed since application start
  # [total_allocated_objects]
  #   The cumulative number of objects allocated since application start
  # [total_freed_objects]
  #   The cumulative number of objects freed since application start
  # [malloc_increase_bytes]
  #   Amount of memory allocated on the heap for objects. Decreased by any \GC
  # [malloc_increase_bytes_limit]
  #   When +:malloc_increase_bytes+ crosses this limit, \GC is triggered
  # [minor_gc_count]
  #   The total number of minor garbage collections run since process start
  # [major_gc_count]
  #   The total number of major garbage collections run since process start
  # [compact_count]
  #   The total number of compactions run since process start
  # [read_barrier_faults]
  #   The total number of times the read barrier was triggered during
  #   compaction
  # [total_moved_objects]
  #   The total number of objects compaction has moved
  # [remembered_wb_unprotected_objects]
  #   The total number of objects without write barriers
  # [remembered_wb_unprotected_objects_limit]
  #   When +:remembered_wb_unprotected_objects+ crosses this limit,
  #   major \GC is triggered
  # [old_objects]
  #   Number of live, old objects which have survived at least 3 garbage collections
  # [old_objects_limit]
  #   When +:old_objects+ crosses this limit, major \GC is triggered
  # [oldmalloc_increase_bytes]
  #   Amount of memory allocated on the heap for objects. Decreased by major \GC
  # [oldmalloc_increase_bytes_limit]
  #   When +:oldmalloc_increase_bytes+ crosses this limit, major \GC is triggered
  #
  # If the optional argument, hash, is given,
  # it is overwritten and returned.
  # This is intended to avoid the probe effect.
  #
  # This method is only expected to work on CRuby.
  def self.stat hash_or_key = nil
    Primitive.gc_stat hash_or_key
  end

  # call-seq:
  #    GC.stat_heap -> Hash
  #    GC.stat_heap(nil, hash) -> Hash
  #    GC.stat_heap(heap_name) -> Hash
  #    GC.stat_heap(heap_name, hash) -> Hash
  #    GC.stat_heap(heap_name, :key) -> Numeric
  #
  # Returns information for heaps in the \GC.
  #
  # If the first optional argument, +heap_name+, is passed in and not +nil+, it
  # returns a +Hash+ containing information about the particular heap.
  # Otherwise, it will return a +Hash+ with heap names as keys and
  # a +Hash+ containing information about the heap as values.
  #
  # If the second optional argument, +hash_or_key+, is given as a +Hash+, it will
  # be overwritten and returned. This is intended to avoid the probe effect.
  #
  # If both optional arguments are passed in and the second optional argument is
  # a symbol, it will return a +Numeric+ value for the particular heap.
  #
  # On CRuby, +heap_name+ is of the type +Integer+ but may be of type +String+
  # on other implementations.
  #
  # The contents of the hash are implementation-specific and may change in
  # the future without notice.
  #
  # If the optional argument, hash, is given, it is overwritten and returned.
  #
  # This method is only expected to work on CRuby.
  #
  # The hash includes the following keys about the internal information in
  # the \GC:
  #
  # [slot_size]
  #   The slot size of the heap in bytes.
  # [heap_allocatable_pages]
  #   The number of pages that can be allocated without triggering a new
  #   garbage collection cycle.
  # [heap_eden_pages]
  #   The number of pages in the eden heap.
  # [heap_eden_slots]
  #   The total number of slots in all of the pages in the eden heap.
  # [heap_tomb_pages]
  #   The number of pages in the tomb heap. The tomb heap only contains pages
  #   that do not have any live objects.
  # [heap_tomb_slots]
  #   The total number of slots in all of the pages in the tomb heap.
  # [total_allocated_pages]
  #   The total number of pages that have been allocated in the heap.
  # [total_freed_pages]
  #   The total number of pages that have been freed and released back to the
  #   system in the heap.
  # [force_major_gc_count]
  #   The number of times this heap has forced major garbage collection cycles
  #   to start due to running out of free slots.
  # [force_incremental_marking_finish_count]
  #   The number of times this heap has forced incremental marking to complete
  #   due to running out of pooled slots.
  #
  def self.stat_heap heap_name = nil, hash_or_key = nil
    Primitive.gc_stat_heap heap_name, hash_or_key
  end

  # call-seq:
  #     GC.config -> hash
  #     GC.config(hash_to_merge) -> merged_hash
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
  # returns the implementation-specific configuration hash (see below):
  #
  #   GC.config(rgengc_allow_full_mark: false)
  #   # => {rgengc_allow_full_mark: false}
  #   GC.config
  #   # => {rgengc_allow_full_mark: false, implementation: "default"}
  #   GC.config(foo: 'bar')
  #   # => {rgengc_allow_full_mark: false}
  #   GC.config
  #   # => {rgengc_allow_full_mark: false, implementation: "default"}
  #
  # <b>All-Implementations Configuration</b>
  #
  # The single read-only entry for all implementations is:
  #
  # - +implementation+:
  #   the string name of the implementation;
  #   for the Ruby default implementation, <tt>'default'</tt>.
  #
  # <b>Implementation-Specific Configuration</b>
  #
  # A \GC implementation maintains its own implementation-specific configuration.
  #
  # For Ruby's default implementation the single entry is:
  #
  # - +rgengc_allow_full_mark+:
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
  #     GC.latest_gc_info -> hash
  #     GC.latest_gc_info(hash) -> hash
  #     GC.latest_gc_info(key) -> value
  #
  # Returns information about the most recent garbage collection.
  #
  # If the argument +hash+ is given and is a Hash object,
  # it is overwritten and returned.
  # This is intended to avoid the probe effect.
  #
  # If the argument +key+ is given and is a Symbol object,
  # it returns the value associated with the key.
  # This is equivalent to <tt>GC.latest_gc_info[key]</tt>.
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
  #    GC.measure_total_time = true/false
  #
  # Enables measuring \GC time.
  # You can get the result with <tt>GC.stat(:time)</tt>.
  # Note that \GC time measurement can cause some performance overhead.
  def self.measure_total_time=(flag)
    Primitive.cstmt! %{
      rb_gc_impl_set_measure_total_time(rb_gc_get_objspace(), flag);
      return flag;
    }
  end

  # call-seq:
  #    GC.measure_total_time -> true/false
  #
  # Returns the measure_total_time flag (default: +true+).
  # Note that measurement can affect the application's performance.
  def self.measure_total_time
    Primitive.cexpr! %{
      RBOOL(rb_gc_impl_get_measure_total_time(rb_gc_get_objspace()))
    }
  end

  # call-seq:
  #    GC.total_time -> int
  #
  # Returns the measured \GC total time in nanoseconds.
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
