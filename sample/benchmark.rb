require 'benchmark'

include Benchmark

n = ARGV[0].to_i.nonzero? || 50000
puts %Q([#{n} times iterations of `a = "1"'])
benchmark(CAPTION, 7, FORMAT) do |x|
  x.report("for:")   {for _ in 1..n; _ = "1"; end} # Benchmark.measure
  x.report("times:") {n.times do   ; _ = "1"; end}
  x.report("upto:")  {1.upto(n) do ; _ = "1"; end}
end

benchmark do
  [
    measure{for _ in 1..n; _ = "1"; end},  # Benchmark.measure
    measure{n.times do   ; _ = "1"; end},
    measure{1.upto(n) do ; _ = "1"; end}
  ]
end
