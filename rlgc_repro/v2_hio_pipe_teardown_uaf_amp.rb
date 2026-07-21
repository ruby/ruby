# RLGCv2 repro (amplifier) for a RARE load-dependent ASAN heap-use-after-free in the
# IO.pipe + Thread + blocking-read(NT-migration) + GC teardown surface (orig: confluence
# hit on h_io_pipe_gc.rb, heap-use-after-free @0x5150000837c0). Run MANY concurrently under
# v2-asan to maximize load; hit rate <1/1500 even amplified. Same family as the zombie-Ractor
# teardown UAF (4177b341e) / fiber_free thread UAF. See FINDING_hio_pipe_uaf / memory
# rlgc-v2-hio-pipe-teardown-uaf. TSan-clean (ASAN-only, GC-sweep-vs-use across coroutine handoff).
# AMPLIFIED h_io_pipe_gc: maximize thread-teardown x GC-sweep overlap under NT migration
Warning[:experimental] = false
12.times.map do |id|
  Ractor.new(id) do |i|
    50.times do |k|
      pipes = []
      threads = []
      4.times do |j|
        r, w = IO.pipe
        pipes << [r, w]
        threads << Thread.new { sleep(rand * 0.0005); w.write("x" * (30 + rand(80))); w.close }
      end
      # blocking reads -> NT migrations
      pipes.each { |r, w| r.read; r.close }
      GC.start                       # sweep while threads tearing down
      threads.each(&:join)
      GC.compact if k % 3 == 0
      Array.new(30) { +"io#{i}-#{k}-#{_1}" }
    end
    :ok
  end
end.each(&:value)
puts "OK hio_amp"
