# binary-trees: GC-heavy weak-scaling benchmark.
# Each unit of work (Ractor / process / the main thread) runs the FULL
# binary-trees workload independently, so total work grows with N.
# Ideal parallel scaling => wall time stays flat as N grows.
#
#   N=<workers>  D=<max depth, default 16>  MODE=single|ractor|fork
#
# MODE=single ignores N and runs one workload on the main Ractor
# (single-Ractor mode: rb_multi_ractor_p() == false).

N    = (ENV['N'] || 1).to_i
MAXD = (ENV['D'] || 16).to_i
MODE = ENV['MODE'] || (N <= 1 ? 'single' : 'ractor')

def item_check(t) = t[0].nil? ? t[1] : t[1] + item_check(t[0]) - item_check(t[2])

def bottom_up_tree(item, depth)
  if depth > 0
    d = depth - 1; ii = 2 * item
    [bottom_up_tree(ii - 1, d), item, bottom_up_tree(ii, d)]
  else
    [nil, item, nil]
  end
end

def work(max_depth)
  min_depth = 4
  bottom_up_tree(0, max_depth + 1)
  long = bottom_up_tree(0, max_depth)
  d = min_depth
  while d <= max_depth
    iters = 2 ** (max_depth - d + min_depth)
    c = 0
    iters.times { |i| c += item_check(bottom_up_tree(i, d)) + item_check(bottom_up_tree(-i, d)) }
    d += 2
  end
  item_check(long)
end

t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
case MODE
when 'single'
  work(MAXD)
when 'fork'
  pids = N.times.map { fork { work(MAXD); exit!(0) } }
  pids.each { |p| Process.wait(p) }
else # ractor
  rs = N.times.map { Ractor.new(MAXD) { |d| work(d) } }
  rs.each(&:value)
end
printf "%.3f\n", Process.clock_gettime(Process::CLOCK_MONOTONIC) - t
