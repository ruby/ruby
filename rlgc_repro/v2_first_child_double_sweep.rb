# RLGCv2 regression: the single->multi Ractor transition (the very first
# Ractor.new) left the creator's `creating_child_objspace` pointer set after the
# child joined vm->ractor.set, so a subsequent global GC enumerated the child's
# objspace TWICE (once via the set, once via the creator). The second sweep --
# after gc_setup_mark_bits reset the page's mark bits -- freed the child's still
# -live main Thread / root Fiber, nulling its ec->thread_ptr; the child then
# crashed in startup with GET_RACTOR()==NULL (vm_locked assert / SEGV@0x88).
#
# Crashed ~40% of runs under RGENGC_CHECK_MODE before the fix; must be 0% after.
# (Also reproduced via bootstraptest/test_ractor.rb tests #104 and #110.)
Warning[:experimental] = false

100.times do
  GC.disable
  Ractor.new {}          # first child: single -> multi transition
  raise "GC.disable flipped" unless GC.disable
  foo = []
  10.times { foo << 1 }
  GC.start               # global GC while the child is still starting up
end
puts "OK v2_first_child_double_sweep"
