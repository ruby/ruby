# RLGCv2: a dead unjoined Ractor's objspace is merged into main by a
# main-targeted postponed job (design_v2.md section 2.3, decision 18),
# not inside the global GC cycle that collected the Ractor object.
#
# Observable from Ruby: incremental marking only starts in the
# single-objspace world (no living workers AND an empty zombie ledger),
# so GC.start(immediate_mark: false) reporting :marking proves every
# orphaned objspace has been absorbed.
Warning[:experimental] = false

def assert(cond, msg)
  raise "FAIL: #{msg}" unless cond
end

30.times do |round|
  # an unjoined Ractor: terminated, never #value'd, reference dropped
  r = Ractor.new { :dead }
  10.times { break if r.inspect =~ /terminated/; sleep 0.01 }
  r = nil

  # several global cycles: one of them collects the Ractor object ->
  # ractor_free disowns the ledger entry + posts the merge job to main
  5.times { GC.start }

  # any Ruby code is a safepoint; the postponed job runs here
  1000.times { Object.new }

  # single-objspace world again? (zombie ledger empty + cnt==1)
  GC.start(full_mark: true, immediate_mark: false, immediate_sweep: false)
  state = GC.latest_gc_info(:state)
  GC.start  # finish the probe cycle
  assert(state == :marking,
         "round #{round}: incremental major did not start (state=#{state});" \
         " an orphaned objspace was not merged")
end

# Never-started Ractors: creation fails after the objspace may already
# exist. The dead Ractor object is then freed by a SINGLE-world local
# GC (not a global one); disown pushes a slotless ledger entry from
# inside that very sweep, turning the world multi-objspace mid-sweep --
# the sweep's pinned-free assert must stay bound to its own mark.
outer = Object.new
10.times do
  begin
    Ractor.new { outer }     # IsolationError: captures an outer local
  rescue Ractor::IsolationError, ArgumentError, TypeError
  end
  begin
    Ractor.new(name: Object.new) { :x }   # bad name after partial setup
  rescue Ractor::IsolationError, ArgumentError, TypeError
  end
end
outer = nil
10.times { GC.start; 1000.times { Object.new } }   # free + merge at safepoints

GC.start(full_mark: true, immediate_mark: false, immediate_sweep: false)
state = GC.latest_gc_info(:state)
GC.start
assert(state == :marking, "never-started Ractors' objspaces not merged (state=#{state})")

# the merged heaps stay healthy
GC.start
puts "ORPHAN_MERGE_PJOB_OK"
