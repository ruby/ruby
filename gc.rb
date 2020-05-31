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
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep
  end

  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep
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
  #     GC.stat(hash) -> hash
  #     GC.stat(:key) -> Numeric
  #
  #  Returns a Hash containing information about the GC.
  #
  #  The hash includes information about internal statistics about GC such as:
  #
  #      {
  #          :count=>0,
  #          :heap_allocated_pages=>24,
  #          :heap_sorted_length=>24,
  #          :heap_allocatable_pages=>0,
  #          :heap_available_slots=>9783,
  #          :heap_live_slots=>7713,
  #          :heap_free_slots=>2070,
  #          :heap_final_slots=>0,
  #          :heap_marked_slots=>0,
  #          :heap_eden_pages=>24,
  #          :heap_tomb_pages=>0,
  #          :total_allocated_pages=>24,
  #          :total_freed_pages=>0,
  #          :total_allocated_objects=>7796,
  #          :total_freed_objects=>83,
  #          :malloc_increase_bytes=>2389312,
  #          :malloc_increase_bytes_limit=>16777216,
  #          :minor_gc_count=>0,
  #          :major_gc_count=>0,
  #          :remembered_wb_unprotected_objects=>0,
  #          :remembered_wb_unprotected_objects_limit=>0,
  #          :old_objects=>0,
  #          :old_objects_limit=>0,
  #          :oldmalloc_increase_bytes=>2389760,
  #          :oldmalloc_increase_bytes_limit=>16777216
  #      }
  #
  #  The contents of the hash are implementation specific and may be changed in
  #  the future.
  #
  #  If the optional argument, hash, is given,
  #  it is overwritten and returned.
  #  This is intended to avoid probe effect.
  #
  #  This method is only expected to work on C Ruby.
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

  def self.compact
    Primitive.rb_gc_compact
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
    Primitive.gc_verify_compaction_references(toward, double_heap)
  end
end

module ObjectSpace
  def garbage_collect full_mark: true, immediate_mark: true, immediate_sweep: true
    Primitive.gc_start_internal full_mark, immediate_mark, immediate_sweep
  end

  module_function :garbage_collect
end
