require 'benchmark'

Benchmark.bmbm do |x|
  x.report('ENV.slice!') do
    10000.times do
      ENV.clear
      ENV['foo'] = 'bar'
      ENV['baz'] = 'qux'
      ENV['bar'] = 'rab'
      _sliced = ENV.slice!('foo', 'baz', 'xxx')
    end
  end
end
