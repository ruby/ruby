require 'benchmark'

Benchmark.bmbm do |x|
  x.report('Array#extract') do
    arrays = Array.new(1000) { (0..10000).to_a }
    arrays.each do |numbers|
      _odd_numbers = numbers.extract { |number| number.odd? }
    end
  end
end
