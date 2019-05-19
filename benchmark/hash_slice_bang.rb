require 'benchmark'

Benchmark.bmbm do |x|
  x.report('Hash#slice!') do
    10000.times do
      hash = { a: 1, b: 2, c: 3, d: 4 }
      _sliced = hash.slice!(:a, :b, :d, :x, :y)
    end
  end
end
