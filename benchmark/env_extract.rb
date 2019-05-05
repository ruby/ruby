require 'benchmark'

Benchmark.bmbm do |x|
  x.report('ENV.extract') do
    10000.times do
      ENV.clear
      ENV['foo'] = 'bar'
      ENV['baz'] = 'qux'
      ENV['bar'] = 'rab'
      _extracted = ENV.extract {|k, v| v == 'qux'}
    end
  end
end
