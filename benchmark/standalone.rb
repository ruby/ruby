require 'benchmark/ips'

$:.unshift File.expand_path('../ext', __dir__)
$:.unshift File.expand_path('../lib', __dir__)

bench, mode = ARGV

if mode == 'pure'
  require 'json/pure'
else
  require 'json/ext'
end

bench_dump = bench == 'dump'
if bench_dump
  p JSON.generator
else
  p JSON.parser
end

str = File.read("#{__dir__}/data/ohai.json")
obj = JSON.load(str)

Benchmark.ips do |x|
  unless RUBY_ENGINE == 'ruby'
    x.warmup = 5
    x.iterations = 5
  end

  if bench_dump
    x.report('JSON.dump(obj)') do # max_nesting: false, allow_nan: true
      JSON.dump(obj)
    end
  else
    x.report('JSON.load(str)') do # max_nesting: false, allow_nan: true, allow_blank: true, create_additions: true
      JSON.load(str)
    end
  end

  x.compare!
end
