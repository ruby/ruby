# Tail-latency probe for the fine-grained-VM-lock change.
# A non-main Ractor repeatedly performs a VM-lock-taking operation (Class.new)
# and records the MAX time of a single operation, while the main Ractor keeps a
# large live heap and hammers allocation to trigger long local GCs.
#
# Before the fine-grained lock: the main Ractor's local GC holds the VM lock for
# the WHOLE GC, so the probe stalls for a full GC (~tens of ms).
# After: the lock is held only for the brief VM-global-table windows, so the
# probe stalls < 1 ms.
#
#   LIVE=<main live objects, default 3_000_000>  ITER=<probe ops, default 30_000>
# Prints the max single-op stall in milliseconds.

LIVE = Array.new((ENV['LIVE'] || 3_000_000).to_i) { Object.new }
ITER = (ENV['ITER'] || 30_000).to_i

r = Ractor.new(ITER) do |iter|
  mx = 0.0
  iter.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Class.new                      # takes the VM lock
    d = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    mx = d if d > mx
  end
  mx
end

stop = false
th = Thread.new { until stop; a = Array.new(1000) { Object.new }; end }  # main: alloc -> local GC
maxstall = r.value
stop = true; th.join
printf "%.3f\n", maxstall * 1000.0   # max stall (ms)
