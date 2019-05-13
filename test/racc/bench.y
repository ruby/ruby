class BenchmarkParser

rule

  target: a a a a a   a a a a a;
  a:      b b b b b   b b b b b;
  b:      c c c c c   c c c c c;
  c:      d d d d d   d d d d d;
  d:      e e e e e   e e e e e;

end

---- inner

def initialize
  @old = [ :e, 'e' ]
  @i = 0
end

def next_token
  return [false, '$'] if @i >= 10_0000
  @i += 1
  @old
end

def parse
  do_parse
end

---- footer

require 'benchmark'

Benchmark.bm do |x|
  x.report { BenchmarkParser.new.parse }
end
