require 'objspace'

# Reports ObjectSpace.memsize_of for hashes of various sizes. Intended to be
# run with `benchmark-driver --runner memory` (the loop count is irrelevant
# for memory measurement). The output line is parseable as a single Integer
# for diff/regression purposes; the comments describe each size point.
SIZES = [16, 64, 256, 1024, 16_384].freeze

hashes = SIZES.map do |n|
  h = {}
  Array.new(n) { |i| "k#{i}".freeze }.each { |k| h[k] = k }
  h
end

# Sum across all sizes -- a single number per run for trend tracking, plus
# per-size detail printed via warn so it shows in --runner output streams.
total = hashes.zip(SIZES).sum do |h, n|
  size = ObjectSpace.memsize_of(h)
  warn format('%-6d entries: %d bytes', n, size)
  size
end

# Loop body kept minimal -- the benchmark-driver runner will execute this
# repeatedly, but only object allocation cost matters for the memory runner.
1_000.times { total }
