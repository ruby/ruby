# RLGCv2 CHECK-mode assertion(s) under concurrent refinement use across Ractors.
# Multi-ractor: ~8/8 under RGENGC_CHECK_MODE (v2-debug). Single-ractor: 0/8.
# ASAN: clean (no UAF) -- this is a CHECK-mode correctness finding, not a
# production memory-safety bug (though see the cross-ractor cc access note below).
#
# Two layered assertions fire from rb_clear_all_refinement_method_cache
# (vm_method.c), reached via `using`:
#
#   1) vm_method.c:853  VM_ASSERT(rb_gc_pointer_to_heap_p(v))
#      The cc_refinement_set is a VM-GLOBAL weak set of refinement callcaches,
#      but rb_gc_pointer_to_heap_p only checks the CURRENT Ractor's objspace
#      (rb_gc_get_objspace()). Entries owned by another Ractor's objspace are
#      live but fail the local membership test. (A cross-objspace variant --
#      rb_gc_pointer_to_heap_p_all_objspaces via rb_gc_vm_each_objspace -- fixes
#      THIS layer; the pruning callback cc_refinement_set_handle_weak_references
#      is already containment-correct via rb_gc_handle_weak_references_alive_p.)
#
#   2) vm_callinfo.h:432 VM_ASSERT(vm_cc_cme: cc->klass != Qundef ||
#      !vm_cc_markable(cc) || vm_cc_invalid_super(cc))   [deeper, after fixing #1]
#      A refinement cc in the set has klass==Qundef (invalidated) yet is still
#      markable and not invalid_super -- a callcache-state inconsistency. This is
#      the real issue: rb_clear_all_refinement_method_cache iterates the VM-global
#      set and reads/invalidates ccs that live in OTHER Ractors' objspaces while
#      holding only RB_VM_LOCK (not a world-stop), so it can observe a cc mid-
#      invalidation by its owner's confined GC. cc-lifecycle-across-Ractors core.
rs = (1..6).map do
  Ractor.new do
    50.times do |i|
      m = Module.new do
        refine String do
          define_method(:rlgc_ext) { "#{self}!#{i}" }
        end
      end
      r = Class.new do
        using m
        define_method(:run) { "abc".rlgc_ext }
      end
      _ = r.new.run rescue nil
      GC.start if i % 10 == 0
    end
    :ok
  end
end
Thread.new { 20.times { GC.compact } }.join
rs.each(&:value)
