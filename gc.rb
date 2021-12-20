# for gc.c

#  The GC module provides an interface to Ruby's mark and
#  sweep garbage collection mechanism.
#
#  Some of the underlying methods are also available via the ObjectSpace
#  module.
#
#  You may obtain information about the operation of the GC through
#  GC::Profiler.
module GC

  #  call-seq:
  #     GC.start                     -> nil
  #     ObjectSpace.garbage_collect  -> nil
  #     include GC; garbage_collect  -> nil
  #     GC.start(full_mark: true, immediate_sweep: true)           -> nil
  #     ObjectSpace.garbage_collect(full_mark: true, immediate_sweep: true) -> nil
  #     include GC; garbage_collect(full_mark: true, immediate_sweep: true) -> nil
  #
  #  Initiates garbage collection, even if manually disabled.
  #
  #  This method is defined with keyword arguments that default to true:
  #
  #     def GC.start(full_mark: true, immediate_sweep: true); end
  #
  #  Use full_mark: false to perform a minor GC.
  #  Use immediate_sweep: false to defer sweeping (use lazy sweep).
  #
  #  Note: These keyword arguments are implementation and version dependent. They
  #  are not guaranteed to be future-compatible, and may be ignored if the
  #  underlying implementation does not support them.
  def self.start full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  #  call-seq:
  #     GC.auto_compact    -> true or false
  #
  #  Returns whether or not automatic compaction has been enabled.
  #
  def self.auto_compact
    Primitive.gc_get_auto_compact
  end

  #  call-seq:
  #     GC.auto_compact = flag
  #
  #  Updates automatic compaction mode.
  #
  #  When enabled, the compactor will execute on every major collection.
  #
  #  Enabling compaction will degrade performance on major collections.
  def self.auto_compact=(flag)
    Primitive.gc_set_auto_compact(flag)
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
  #  Returns current status of GC stress mode.
  def self.stress
    Primitive.gc_stress_get
  end

  #  call-seq:
  #    GC.stress = flag          -> flag
  #
  #  Updates the GC stress mode.
  #
  #  When stress mode is enabled, the GC is invoked at every GC opportunity:
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
  #  The number of times GC occurred.
  #
  #  It returns the number of times GC occurred since the process started.
  def self.count
    Primitive.gc_count
  end

  #  call-seq:
  #     GC.stat -> Hash
  #     GC.stat(hash) -> Hash
  #     GC.stat(:key) -> Numeric
  #
  #  Returns a Hash containing information about the GC.
  #
  #  The contents of the hash are implementation specific and may change in
  #  the future without notice.
  #
  #  The hash includes information about internal statistics about GC such as:
  #
  #  [count]
  #    The total number of garbage collections ran since application start
  #    (count includes both minor and major garbage collections)
  #  [heap_allocated_pages]
  #    The total number of `:heap_eden_pages` + `:heap_tomb_pages`
  #  [heap_sorted_length]
  #    The number of pages that can fit into the buffer that holds references to
  #    all pages
  #  [heap_allocatable_pages]
  #    The total number of pages the application could allocate without additional GC
  #  [heap_available_slots]
  #    The total number of slots in all `:heap_allocated_pages`
  #  [heap_live_slots]
  #    The total number of slots which contain live objects
  #  [heap_free_slots]
  #    The total number of slots which do not contain live objects
  #  [heap_final_slots]
  #    The total number of slots with pending finalizers to be run
  #  [heap_marked_slots]
  #    The total number of objects marked in the last GC
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
  #    Amount of memory allocated on the heap for objects. Decreased by any GC
  #  [malloc_increase_bytes_limit]
  #    When `:malloc_increase_bytes` crosses this limit, GC is triggered
  #  [minor_gc_count]
  #    The total number of minor garbage collections run since process start
  #  [major_gc_count]
  #    The total number of major garbage collections run since process start
  #  [remembered_wb_unprotected_objects]
  #    The total number of objects without write barriers
  #  [remembered_wb_unprotected_objects_limit]
  #    When `:remembered_wb_unprotected_objects` crosses this limit,
  #    major GC is triggered
  #  [old_objects]
  #    Number of live, old objects which have survived at least 3 garbage collections
  #  [old_objects_limit]
  #    When `:old_objects` crosses this limit, major GC is triggered
  #  [oldmalloc_increase_bytes]
  #    Amount of memory allocated on the heap for objects. Decreased by major GC
  #  [oldmalloc_increase_bytes_limit]
  #    When `:old_malloc_increase_bytes` crosses this limit, major GC is triggered
  #
  #  If the optional argument, hash, is given,
  #  it is overwritten and returned.
  #  This is intended to avoid probe effect.
  #
  #  This method is only expected to work on CRuby.
  def self.stat hash_or_key = nil
    Primitive.gc_stat hash_or_key
  end

  #  call-seq:
  #     GC.latest_gc_info -> {:gc_by=>:newobj}
  #     GC.latest_gc_info(hash) -> hash
  #     GC.latest_gc_info(:major_by) -> :malloc
  #
  #  Returns information about the most recent garbage collection.
  #
  # If the optional argument, hash, is given,
  # it is overwritten and returned.
  # This is intended to avoid probe effect.
  def self.latest_gc_info hash_or_key = nil
    Primitive.gc_latest_gc_info hash_or_key
  end

  #  call-seq:
  #     GC.latest_compact_info -> {:considered=>{:T_CLASS=>11}, :moved=>{:T_CLASS=>11}}
  #
  #  Returns information about object moved in the most recent GC compaction.
  #
  # The returned hash has two keys :considered and :moved.  The hash for
  # :considered lists the number of objects that were considered for movement
  # by the compactor, and the :moved hash lists the number of objects that
  # were actually moved.  Some objects can't be moved (maybe they were pinned)
  # so these numbers can be used to calculate compaction efficiency.
  def self.latest_compact_info
    Primitive.gc_compact_stats
  end

  #  call-seq:
  #     GC.compact
  #
  # This function compacts objects together in Ruby's heap.  It eliminates
  # unused space (or fragmentation) in the heap by moving objects in to that
  # unused space.  This function returns a hash which contains statistics about
  # which objects were moved.  See `GC.latest_gc_info` for details about
  # compaction statistics.
  #
  # This method is implementation specific and not expected to be implemented
  # in any implementation besides MRI.
  def self.compact
    Primitive.gc_compact
  end

  # call-seq:
  #    GC.verify_compaction_references(toward: nil, double_heap: false) -> hash
  #
  # Verify compaction reference consistency.
  #
  # This method is implementation specific.  During compaction, objects that
  # were moved are replaced with T_MOVED objects.  No object should have a
  # reference to a T_MOVED object after compaction.
  #
  # This function doubles the heap to ensure room to move all objects,
  # compacts the heap to make sure everything moves, updates all references,
  # then performs a full GC.  If any object contains a reference to a T_MOVED
  # object, that object should be pushed on the mark stack, and will
  # make a SEGV.
  def self.verify_compaction_references(toward: nil, double_heap: false)
    Primitive.gc_verify_compaction_references(double_heap, toward == :empty)
  end

  # call-seq:
  #     GC.using_rvargc? -> true or false
  #
  # Returns true if using experimental feature Variable Width Allocation, false
  # otherwise.
  def self.using_rvargc? # :nodoc:
    GC::INTERNAL_CONSTANTS[:SIZE_POOL_COUNT] > 1
  end


  # call-seq:
  #    GC.measure_total_time = true/false
  #
  # Enable to measure GC time.
  # You can get the result with <tt>GC.stat(:time)</tt>.
  # Note that GC time measurement can cause some performance overhead.
  def self.measure_total_time=(flag)
    Primitive.cstmt! %{
      rb_objspace.flags.measure_gc = RTEST(flag) ? TRUE : FALSE;
      return flag;
    }
  end

  # call-seq:
  #    GC.measure_total_time -> true/false
  #
  # Return measure_total_time flag (default: +true+).
  # Note that measurement can affect the application performance.
  def self.measure_total_time
    Primitive.cexpr! %{
      RBOOL(rb_objspace.flags.measure_gc)
    }
  end

  # call-seq:
  #    GC.total_time -> int
  #
  # Return measured GC total time in nano seconds.
  def self.total_time
    Primitive.cexpr! %{
      ULL2NUM(rb_objspace.profile.total_time_ns)
    }
  end
end

module ObjectSpace
  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep, false
  end

  module_function :garbage_collect
end
