# for gc.c

#  The \GC module provides an interface to Ruby's mark and
#  sweep garbage collection mechanism.
#
#  Some of the underlying methods are also available via the ObjectSpace
#  module.
#
#  You may obtain information about the operation of the \GC through
#  GC::Profiler.
module GC

  # Initiates garbage collection, even if manually disabled.
  #
  # The +full_mark+ keyword argument determines whether or not to perform a
  # major garbage collection cycle. When set to +true+, a major garbage
  # collection cycle is ran, meaning all objects are marked. When set to
  # +false+, a minor garbage collection cycle is ran, meaning only young
  # objects are marked.
  #
  # The +immediate_mark+ keyword argument determines whether or not to perform
  # incremental marking. When set to +true+, marking is completed during the
  # call to this method. When set to +false+, marking is performed in steps
  # that is interleaved with future Ruby code execution, so marking might not
  # be completed during this method call. Note that if +full_mark+ is +false+
  # then marking will always be immediate, regardless of the value of
  # +immediate_mark+.
  #
  # The +immediate_sweep+ keyword argument determines whether or not to defer
  # sweeping (using lazy sweep). When set to +false+, sweeping is performed in
  # steps that is interleaved with future Ruby code execution, so sweeping might
  # not be completed during this method call. When set to +true+, sweeping is
  # completed during the call to this method.
  #
  # Note: These keyword arguments are implementation and version dependent. They
  # are not guaranteed to be future-compatible, and may be ignored if the
  # underlying implementation does not support them.
  def self.start full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  # Alias of GC.start
  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  #  call-seq:
  #     GC.enable    -> true or false
  #
  #  Enables garbage collection, returning +true+ if garbage
  #  collection was previously disabled.
  #
  #     GC.disable   #=> false
  #     GC.enable    #=> true
  #     GC.enable    #=> false
  #
  def self.enable
    Primitive.gc_enable
  end

  #  call-seq:
  #     GC.disable    -> true or false
  #
  #  Disables garbage collection, returning +true+ if garbage
  #  collection was already disabled.
  #
  #     GC.disable   #=> false
  #     GC.disable   #=> true
  def self.disable
    Primitive.gc_disable
  end

  #  call-seq:
  #    GC.stress	    -> integer, true or false
  #
  #  Returns current status of \GC stress mode.
  def self.stress
    Primitive.gc_stress_get
  end

  #  call-seq:
  #    GC.stress = flag          -> flag
  #
  #  Updates the \GC stress mode.
  #
  #  When stress mode is enabled, the \GC is invoked at every \GC opportunity:
  #  all memory and object allocations.
  #
  #  Enabling stress mode will degrade performance, it is only for debugging.
  #
  #  flag can be true, false, or an integer bit-ORed following flags.
  #    0x01:: no major GC
  #    0x02:: no immediate sweep
  #    0x04:: full mark after malloc/calloc/realloc
  def self.stress=(flag)
    Primitive.gc_stress_set_m flag
  end

  #  call-seq:
  #     GC.count -> Integer
  #
  #  The number of times \GC occurred.
  #
  #  It returns the number of times \GC occurred since the process started.
  def self.count
    Primitive.gc_count
  end

  #  call-seq:
  #     GC.stat -> Hash
  #     GC.stat(hash) -> Hash
  #     GC.stat(:key) -> Numeric
  #
  #  Returns a Hash containing information about the \GC.
  #
  #  The contents of the hash are implementation specific and may change in
  #  the future without notice.
  #
  #  The hash includes information about internal statistics about \GC such as:
  #
  #  [count]
  #    The total number of garbage collections ran since application start
  #    (count includes both minor and major garbage collections)
  #  [time]
  #    The total time spent in garbage collections (in milliseconds)
  #  [heap_allocated_pages]
  #    The total number of +:heap_eden_pages+ + +:heap_tomb_pages+
  #  [heap_sorted_length]
  #    The number of pages that can fit into the buffer that holds references to
  #    all pages
  #  [heap_allocatable_pages]
  #    The total number of pages the application could allocate without additional \GC
  #  [heap_available_slots]
  #    The total number of slots in all +:heap_allocated_pages+
  #  [heap_live_slots]
  #    The total number of slots which contain live objects
  #  [heap_free_slots]
  #    The total number of slots which do not contain live objects
  #  [heap_final_slots]
  #    The total number of slots with pending finalizers to be run
  #  [heap_marked_slots]
  #    The total number of objects marked in the last \GC
  #  [heap_eden_pages]
  #    The total number of pages which contain at least one live slot
  #  [heap_tomb_pages]
  #    The total number of pages which do not contain any live slots
  #  [total_allocated_pages]
  #    The cumulative number of pages allocated since application start
  #  [total_freed_pages]
  #    The cumulative number of pages freed since application start
  #  [total_allocated_objects]
  #    The cumulative number of objects allocated since application start
  #  [total_freed_objects]
  #    The cumulative number of objects freed since application start
  #  [malloc_increase_bytes]
  #    Amount of memory allocated on the heap for objects. Decreased by any \GC
  #  [malloc_increase_bytes_limit]
  #    When +:malloc_increase_bytes+ crosses this limit, \GC is triggered
  #  [minor_gc_count]
  #    The total number of minor garbage collections run since process start
  #  [major_gc_count]
  #    The total number of major garbage collections run since process start
  #  [compact_count]
  #    The total number of compactions run since process start
  #  [read_barrier_faults]
  #    The total number of times the read barrier was triggered during
  #    compaction
  #  [total_moved_objects]
  #    The total number of objects compaction has moved
  #  [remembered_wb_unprotected_objects]
  #    The total number of objects without write barriers
  #  [remembered_wb_unprotected_objects_limit]
  #    When +:remembered_wb_unprotected_objects+ crosses this limit,
  #    major \GC is triggered
  #  [old_objects]
  #    Number of live, old objects which have survived at least 3 garbage collections
  #  [old_objects_limit]
  #    When +:old_objects+ crosses this limit, major \GC is triggered
  #  [oldmalloc_increase_bytes]
  #    Amount of memory allocated on the heap for objects. Decreased by major \GC
  #  [oldmalloc_increase_bytes_limit]
  #    When +:old_malloc_increase_bytes+ crosses this limit, major \GC is triggered
  #
  #  If the optional argument, hash, is given,
  #  it is overwritten and returned.
  #  This is intended to avoid probe effect.
  #
  #  This method is only expected to work on CRuby.
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
  # If the second optional argument, +hash_or_key+, is given as +Hash+, it will
  # be overwritten and returned. This is intended to avoid the probe effect.
  #
  # If both optional arguments are passed in and the second optional argument is
  # a symbol, it will return a +Numeric+ of the value for the particular heap.
  #
  # On CRuby, +heap_name+ is of the type +Integer+ but may be of type +String+
  # on other implementations.
  #
  # The contents of the hash are implementation specific and may change in
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
  #   The number of times major garbage collection cycles this heap has forced
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
  #     GC.config(hash) -> hash
  #
  # Sets or gets information about the current GC config.
  #
  # Configuration parameters are GC implementation specific and may change
  # without notice.
  #
  # This method can be called without parameters to retrieve the current config.
  #
  # This method can also be called with a +Hash+ argument to assign values to
  # valid config keys. Config keys missing from the passed +Hash+ will be left
  # unmodified.
  #
  # If a key/value pair is passed to this function that does not correspond to
  # a valid config key for the GC implementation being used, no config will be
  # updated, the key will be present in the returned Hash, and it's value will
  # be +nil+. This is to facilitate easy migration between GC implementations.
  #
  # In both call-seqs the return value of <code>GC.config</code> will be a +Hash+
  # containing the most recent full configuration. ie. All keys and values
  # defined by the specific GC implementation being used. In the case of a
  # config update, the return value will include the new values being updated.
  #
  # This method is only expected to work on CRuby.
  #
  # Valid config keys for Ruby's default GC implementation are:
  #
  # [rgengc_allow_full_mark]
  #   Control whether the GC is allowed to run a full mark (young & old objects).
  #
  #   When +true+ GC interleaves major and minor collections. This is default. GC
  #   will function as intended.
  #
  #   When +false+, the GC will never trigger a full marking cycle unless
  #   explicitly requested by user code. Instead only a minor mark will run -
  #   only young objects will be marked. When the heap space is exhausted, new
  #   pages will be allocated immediately instead of running a full mark.
  #
  #   A flag will be set to notify that a full mark has been
  #   requested. This flag is accessible using
  #   <code>GC.latest_gc_info(:needs_major_by)</code>
  #
  #   The user can trigger a major collection at any time using
  #   <code>GC.start(full_mark: true)</code>
  #
  #   When +false+. Young to Old object promotion is disabled. For performance
  #   reasons it is recommended to warmup an application using +Process.warmup+
  #   before setting this parameter to +false+.
  def self.config hash = nil
    return Primitive.gc_config_get unless hash

    Primitive.gc_config_set hash
  end

  # call-seq:
  #     GC.latest_gc_info -> hash
  #     GC.latest_gc_info(hash) -> hash
  #     GC.latest_gc_info(:major_by) -> :malloc
  #
  # Returns information about the most recent garbage collection.
  #
  # If the optional argument, hash, is given,
  # it is overwritten and returned.
  # This is intended to avoid probe effect.
  def self.latest_gc_info hash_or_key = nil
    Primitive.gc_latest_gc_info hash_or_key
  end

  # call-seq:
  #    GC.measure_total_time = true/false
  #
  # Enable to measure \GC time.
  # You can get the result with <tt>GC.stat(:time)</tt>.
  # Note that \GC time measurement can cause some performance overhead.
  def self.measure_total_time=(flag)
    Primitive.cstmt! %{
      return rb_gc_impl_set_measure_total_time(rb_gc_get_objspace(), flag);
    }
  end

  # call-seq:
  #    GC.measure_total_time -> true/false
  #
  # Return measure_total_time flag (default: +true+).
  # Note that measurement can affect the application performance.
  def self.measure_total_time
    Primitive.cexpr! %{
      rb_gc_impl_get_measure_total_time(rb_gc_get_objspace())
    }
  end

  # call-seq:
  #    GC.total_time -> int
  #
  # Return measured \GC total time in nano seconds.
  def self.total_time
    Primitive.cexpr! %{
      rb_gc_impl_get_profile_total_time(rb_gc_get_objspace())
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
