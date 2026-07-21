# Hardware-ceiling baseline: pure integer compute, ZERO allocation, ZERO GC.
# Run in N Ractors to measure how much parallel degradation comes purely from
# the machine (turbo-clock reduction under multi-core load + SMT), independent
# of any GC / Ractor effect.
#
#   N=<workers>  W=<loop iterations, default 120_000_000>

N = (ENV['N'] || 1).to_i
W = (ENV['W'] || 120_000_000).to_i

def busy(x)
  s = 0; i = 0
  while i < x; s += (i * i) % 7; i += 1; end
  s
end

t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
if N <= 1
  busy(W)
else
  rs = N.times.map { Ractor.new(W) { |w| busy(w) } }
  rs.each(&:value)
end
printf "%.3f\n", Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
