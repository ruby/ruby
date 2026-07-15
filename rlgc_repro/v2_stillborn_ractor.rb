# RLGCv2: Ractor creation that fails after the child objspace exists
# (rb_proc_isolate_bang's IsolationError) must not leave the creator's
# creating_child_objspace cover behind.
#
# Without the failure-path cleanup in rb_thread_create_ractor, with the
# stale cover in place:
#  1. a global GC sweep collects the dead child Ractor object ->
#     ractor_free disowns its objspace into the zombie ledger while the
#     cover still names it -> the next global GC enumerates the same
#     objspace twice (ledger + cover) = the b3b132728 double-sweep shape;
#  2. once main's orphan-merge postponed job absorbs the shell, the cover
#     dangles and rlgc_global_gc's whole-VM walk reads freed memory
#     (flaky UAF/SEGV, the trace-verify family).
#
# The stale cover is wiped by the creator's NEXT Ractor.new, so the
# trigger needs: multi-objspace held by a worker created BEFORE the
# stillborn attempt, then global GCs with no further Ractor.new.
Warning[:experimental] = false

x = 42 # captured outer local => IsolationError at Ractor.new

# Phase 1: focused window. Keep a long-lived worker so every explicit
# GC.start below runs the GLOBAL cycle (multi-objspace), while the
# creator's cover stays untouched after the stillborn attempt.
worker = Ractor.new do
  loop { break if Ractor.receive == :quit }
end

begin
  Ractor.new { x }
  raise "unexpected: isolation error did not fire"
rescue Ractor::IsolationError
end

# global cycle 1: collects the stillborn Ractor object -> disown (ledger)
# global cycle 2: double-enumerates ledger + stale cover
# absorb happens at a safepoint in between -> later cycles read the
# freed shell through the dangling cover
10.times { GC.start; 500.times { Object.new } }
GC.verify_internal_consistency

worker.send(:quit)
worker.value

# Phase 2: churn (many stillborns racing collection/absorb)
200.times do |i|
  begin
    Ractor.new { x }
    raise "unexpected: isolation error did not fire"
  rescue Ractor::IsolationError
  end

  if (i % 20).zero?
    Ractor.new { :ok }.value
    GC.start
  end
  GC.verify_internal_consistency if (i % 50).zero?
end

GC.start
GC.start
ObjectSpace.each_object(Class) { |c| }
GC.verify_internal_consistency
puts "OK v2_stillborn_ractor"
