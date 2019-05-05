require 'benchmark'

Benchmark.bmbm do |x|
  x.report('Hash#extract') do
    10000.times do
      hash_for_extract = { a: 1, b: 2, c: 3, d: 4 }
      _executed = hash_for_extract.extract {|k, v| v > 2}
    end
  end
end
