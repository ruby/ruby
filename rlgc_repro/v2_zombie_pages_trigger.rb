# RLGCv2: design_v2.md section 2.2 trigger 3 -- a global GC fires when
# terminated-but-uninherited (slotted, still joinable) Ractors retain
# enough heap PAGES, not heads. Their Ractor objects stay referenced
# here, so neither Ractor#value nor the orphan merge ever runs; only
# the page trigger can reclaim their garbage.
#
# Each worker retains ~8k 512-byte strings in a ractor-local global, so
# its zombie objspace keeps ~80+ pages; 8 workers comfortably exceed
# RLGC_ZOMBIE_PAGES_TRIGGER (256). The escalated cycle is observable as
# a major GC the main Ractor never asked for. The global's refresh then
# re-measures the swept zombies, so the trigger stops re-firing -- a
# second batch must push it over the bar again.
Warning[:experimental] = false

def wait_terminated(rs)
  rs.each { |r| 50.times { break if r.inspect =~ /terminated/; sleep 0.01 } }
end

def spawn_fat_zombies(n)
  rs = n.times.map do
    Ractor.new do
      retain = Array.new(8_000) { +"x" * 512 }
      Ractor.yield nil if false   # keep the local visible to the end
      retain.size
      :done
    end
  end
  wait_terminated(rs)
  rs   # keep the Ractor objects referenced: slotted zombies
end

zombies = spawn_fat_zombies(8)

before = GC.stat[:major_gc_count]
spin = 0
while GC.stat[:major_gc_count] == before && spin < 2_000_000
  Object.new
  spin += 1
end
raise "page trigger did not escalate to a global GC" if GC.stat[:major_gc_count] == before
GC.verify_internal_consistency

# After the global the zombies' garbage is gone and the ledger was
# re-measured. Empty pages leave a heap gradually (the freeable-pages
# budget), so a few more cycles may fire while the count converges
# below the threshold -- but it must CONVERGE, not storm.
after_first = GC.stat[:major_gc_count]
300_000.times { Object.new }
majors = GC.stat[:major_gc_count] - after_first
raise "trigger storm: #{majors} majors on stale zombie pages" if majors > 8

# a second batch pushes it over the bar again
zombies.concat(spawn_fat_zombies(8))
before2 = GC.stat[:major_gc_count]
spin = 0
while GC.stat[:major_gc_count] == before2 && spin < 2_000_000
  Object.new
  spin += 1
end
raise "second batch did not re-trigger" if GC.stat[:major_gc_count] == before2
GC.verify_internal_consistency

zombies = nil
3.times { GC.start }     # collect the Ractor objects -> disown -> pjob merge
1000.times { Object.new }
GC.verify_internal_consistency

puts "ZOMBIE_PAGES_TRIGGER_OK"
