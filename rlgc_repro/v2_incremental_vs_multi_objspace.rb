# RLGCv2: an incremental mark cycle must never span the single->multi
# objspace transition.
#
# Without the settle in vm_insert_ractor0 (rb_gc_finish_in_flight_gc):
#  * a worker-driven GLOBAL cycle hits main mid-incremental: step 5
#    clears during_incremental_marking but the gray mark stack keeps its
#    snapshot, wrecking main's GC state machine -- deterministic
#      [BUG] page_sweep: freeing pinned slot T_IMEMO (shareable=0 shref=1)
#    on the first iteration of the first loop below.
#  * Ractor#value's absorb splices the dead worker's pages into main's
#    half-marked heap (second loop; survives only by the finish-time
#    root rescan, so it is exercised here as a regression canary).
#
# GC.start(immediate_mark: false) starts an incremental major and
# returns with the mark phase in flight.
Warning[:experimental] = false

RETAIN = []
400_000.times { RETAIN << ("x" * 8) }
GC.start

# Hazard 1: global cycle while main is mid-incremental-mark
40.times do |round|
  GC.start(full_mark: true, immediate_mark: false, immediate_sweep: false)
  r = Ractor.new { GC.start; :done }     # worker drives a global cycle
  raise unless r.value == :done
  200_000.times { Object.new }
  GC.start
  RETAIN[round] = +"q"
end

# Hazard 2: absorb (Ractor#value inheritance) while main is mid-mark
30.times do
  GC.start(full_mark: true, immediate_mark: false, immediate_sweep: false)
  r = Ractor.new do
    Array.new(50_000) { |i| "live-#{i}" }
  end
  v = r.value
  300_000.times { Object.new }
  raise "size" unless v.size == 50_000
  raise "elem" unless v[12_345] == "live-12345"
  total = 0
  v.each { |s| total += s.size }
  raise "sum" unless total > 0
end

puts "INC_VS_MULTI_OK"
