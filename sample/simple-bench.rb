require 'benchmark'

def foo0
end
def foo3 a, b, c
end
def foo6 a, b, c, d, e, f
end

def iter0
  yield
end

def iter1
  yield 1
end

def iter3
  yield 1, 2, 3
end

def iter6
  yield 1, 2, 3, 4, 5, 6
end

(1..6).each{|i|
  kws = (1..i).map{|e| "k#{e}: #{e}"}
  eval %Q{
    def foo_kw#{i}(#{kws.join(', ')})
    end
  }

  kws = (1..i).map{|e| "k#{e}:"}
  eval %Q{
    def foo_required_kw#{i}(#{kws.join(', ')})
    end
  }
}

(1..6).each{|i|
  kws = (1..i).map{|e| "k#{e}: #{e} + 1"}
  eval %Q{
    def foo_complex_kw#{i}(#{kws.join(', ')})
    end
  }
}

(1..6).each{|i|
  kws = (1..i).map{|e| "k#{e}: #{e}"}
  eval %Q{
    def iter_kw#{i}
      yield #{kws.join(', ')}
    end
  }
}

ary1 = [1]
ary2 = [[1, 2, 3, 4, 5]]

test_methods = %Q{
  # empty 1
  # empty 2
  foo0
  foo3 1, 2, 3
  foo6 1, 2, 3, 4, 5, 6
  foo_kw1
  foo_kw2
  foo_kw3
  foo_kw4
  foo_kw5
  foo_kw6
  foo_kw6 k1: 1
  foo_kw6 k1: 1, k2: 2
  foo_kw6 k1: 1, k2: 2, k3: 3
  foo_kw6 k1: 1, k2: 2, k3: 3, k4: 4
  foo_kw6 k1: 1, k2: 2, k3: 3, k4: 4, k5: 5
  foo_kw6 k1: 1, k2: 2, k3: 3, k4: 4, k5: 5, k6: 6
  foo_required_kw1 k1: 1
  foo_required_kw2 k1: 1, k2: 2
  foo_required_kw3 k1: 1, k2: 2, k3: 3
  foo_required_kw4 k1: 1, k2: 2, k3: 3, k4: 4
  foo_required_kw5 k1: 1, k2: 2, k3: 3, k4: 4, k5: 5
  foo_required_kw6 k1: 1, k2: 2, k3: 3, k4: 4, k5: 5, k6: 6
  foo_complex_kw1
  foo_complex_kw2
  foo_complex_kw3
  foo_complex_kw4
  foo_complex_kw5
  foo_complex_kw6
  foo_complex_kw6 k1: 1
  foo_complex_kw6 k1: 1, k2: 2
  foo_complex_kw6 k1: 1, k2: 2, k3: 3
  foo_complex_kw6 k1: 1, k2: 2, k3: 3, k4: 4
  foo_complex_kw6 k1: 1, k2: 2, k3: 3, k4: 4, k5: 5
  foo_complex_kw6 k1: 1, k2: 2, k3: 3, k4: 4, k5: 5, k6: 6
  iter0{}
  iter1{}
  iter1{|a|}
  iter3{}
  iter3{|a|}
  iter3{|a, b, c|}
  iter6{}
  iter6{|a|}
  iter6{|a, b, c, d, e, f, g|}
  iter0{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  iter_kw1{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  iter_kw2{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  iter_kw3{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  iter_kw4{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  iter_kw5{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  iter_kw6{|k1: nil, k2: nil, k3: nil, k4: nil, k5: nil, k6: nil|}
  ary1.each{|e|}
  ary1.each{|e,|}
  ary1.each{|a, b, c, d, e|}
  ary2.each{|e|}
  ary2.each{|e,|}
  ary2.each{|a, b, c, d, e|}
}

N = 10_000_000

max_line = test_methods.each_line.max_by{|line| line.strip.size}
max_size = max_line.strip.size

Benchmark.bm(max_size){|x|

  str = test_methods.each_line.map{|line| line.strip!
    next if line.empty?
    %Q{
      x.report(#{line.dump}){
        i = 0
        while i<#{N}
          #{line}
          i+=1
        end
      }
    }
  }.join("\n")
  eval str
}
