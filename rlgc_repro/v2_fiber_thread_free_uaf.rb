# RLGCv2 heap-use-after-free: fiber_free (cont.c:1338) dereferences an
# already-freed rb_thread_t through a non-root fiber's dangling back-pointer
# fiber->cont.saved_ec.thread_ptr.
#
# Mechanism: the Fiber/Thread teardown detach handshake (commit 1dcfbbc996)
# has thread_free detach only the thread's *active/root* fiber (th->ec->fiber_ptr),
# but every NON-root fiber also holds saved_ec.thread_ptr pointing at the thread.
# When a global GC sweeps a dead thread and its non-root fibers together and the
# thread is freed first, fiber_free reads th->ec off the freed thread struct.
#
# Deterministic under ASAN (v2-asan): ~8/8.  Needs several concurrent threads per
# Ractor each creating non-root fibers, plus GC churn, so the sweep frees a thread
# before its fibers.
rs = (1..6).map do
  Ractor.new do
    (1..4).map { Thread.new { 20.times { f = Fiber.new { 1 }; f.resume; GC.start if rand < 0.1 } } }.each(&:join)
    :ok
  end
end
Thread.new { 25.times { GC.compact } }.join
rs.each(&:value)
