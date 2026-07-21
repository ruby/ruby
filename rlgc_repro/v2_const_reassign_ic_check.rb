# CHECK-mode constant-cache (inline cache) consistency assertion under concurrent
# constant REASSIGNMENT across Ractors. ~6/10 under RGENGC_CHECK_MODE (v2-debug);
# ASAN clean (CHECK-only, no memory corruption).
#
#   vm_insnhelper.c:6571  rb_vm_opt_getconstant_path:
#     VM_ASSERT(val == vm_get_ev_const_chain(ec, segments))
#
# The inline constant cache (ic->entry) hits (vm_ic_hit_p true) and returns the
# cached value, but the freshly-recomputed constant chain differs: the IC was not
# invalidated in step with another Ractor reassigning the same constant. The IC and
# its invalidation (global constant serial) are upstream VM machinery (git blame
# d2a0e98c7, 0 RLGC markers); RLGC does not touch the constant table or its
# invalidation. Setting a constant to a SHAREABLE value from a non-main Ractor is
# legal (variable.c:3995 only forbids non-shareable values), so this is a legal but
# inherently racy operation whose IC invalidation isn't synchronized across Ractors.
#
# CONFIRMED UPSTREAM (constant-cache invalidation vs concurrent cross-Ractor reassign),
# NOT RLGC: a from-scratch CHECK build of the true merge-base 26f09eb6a
# (RGENGC_CHECK_MODE=2, no RLGC) asserts rb_vm_opt_getconstant_path 12/12 on this
# exact workload -- more reliably than RLGC (6/10). The IC + global-constant-serial
# invalidation is upstream; RLGC does not touch it. Control: read-only shared
# constants do NOT trip it (reassignment is the trigger).
rs = (1..6).map do
  Ractor.new do
    300.times { |i| K_RLGC_PROBE = Object.new.freeze; _ = K_RLGC_PROBE }
    :ok
  end
end
rs.each(&:value) rescue nil
