# RLGCv2 repro (amplifier) for a RARE load-dependent ASAN heap-use-after-free in the
# IO.pipe + Thread + blocking-read(NT-migration) + GC teardown surface (orig: confluence
# hit on h_io_pipe_gc.rb, heap-use-after-free @0x5150000837c0). Run MANY concurrently under
# v2-asan to maximize load; hit rate <1/1500 even amplified. Same family as the zombie-Ractor
# teardown UAF (4177b341e) / fiber_free thread UAF. See FINDING_hio_pipe_uaf / memory
# rlgc-v2-hio-pipe-teardown-uaf. TSan-clean (ASAN-only, GC-sweep-vs-use across coroutine handoff).
# hio_amp + GC.stress: every allocation triggers a full GC sweep -> maximal sweep x teardown overlap
Warning[:experimental] = false
8.times.map do |id|
  Ractor.new(id) do |i|
    GC.stress = true
    15.times do |k|
      r, w = IO.pipe
      t = Thread.new { w.write("x" * 40); w.close }
      r.read          # blocks -> NT migration; GC.stress -> sweep churn
      r.close
      t.join          # thread teardown while GC.stress sweeps every alloc
      Array.new(8) { +"io#{i}-#{k}" }   # allocs -> each triggers sweep
    end
    GC.stress = false
    :ok
  end
end.each(&:value)
puts "OK hio_amp2"
