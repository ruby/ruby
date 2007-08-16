assert_equal %q{1}, %q{
  1.times{
    begin
      a = 1
    ensure
      foo = nil
    end
  }
}
assert_equal %q{2}, %q{
  [1,2,3].find{|x| x == 2}
}
assert_equal %q{2}, %q{
  class E
    include Enumerable
    def each(&block)
      [1, 2, 3].each(&block)
    end
  end
  E.new.find {|x| x == 2 }
}
assert_equal %q{6}, %q{
  sum = 0
  for x in [1, 2, 3]
    sum += x
  end
  sum
}
assert_equal %q{15}, %q{
  sum = 0
  for x in (1..5)
    sum += x
  end
  sum
}
assert_equal %q{0}, %q{
  sum = 0
  for x in []
    sum += x
  end
  sum
}
assert_equal %q{1}, %q{
  ans = []
  1.times{
    for n in 1..3
      a = n
      ans << a
    end
  }
}
assert_equal %q{1..3}, %q{
  ans = []
  for m in 1..3
    for n in 1..3
      a = [m, n]
      ans << a
    end
  end
}
assert_equal %q{[1, 2, 3]}, %q{
  (1..3).to_a
}
assert_equal %q{[4, 8, 12]}, %q{
  (1..3).map{|e|
    e * 4
  }
}
assert_equal %q{[1, 2, 3]}, %q{
  class C
    include Enumerable
    def each
      [1,2,3].each{|e|
        yield e
      }
    end
  end
  
  C.new.to_a
}
assert_equal %q{[4, 5, 6]}, %q{
  class C
    include Enumerable
    def each
      [1,2,3].each{|e|
        yield e
      }
    end
  end
  
  C.new.map{|e|
    e + 3
  }
}
assert_equal %q{100}, %q{
  def m
    yield
  end
  def n
    yield
  end

  m{
    n{
      100
    }
  }
}
assert_equal %q{20}, %q{
  def m
    yield 1
  end
  
  m{|ib|
    m{|jb|
      i = 20
    }
  }
}
assert_equal %q{2}, %q{
  def m
    yield 1
  end
  
  m{|ib|
    m{|jb|
      ib = 20
      kb = 2
    }
  }
}
assert_equal %q{3}, %q{
  def iter1
    iter2{
      yield
    }
  end
  
  def iter2
    yield
  end
  
  iter1{
    jb = 2
    iter1{
      jb = 3
    }
    jb
  }
}
assert_equal %q{2}, %q{
  def iter1
    iter2{
      yield
    }
  end
  
  def iter2
    yield
  end
  
  iter1{
    jb = 2
    iter1{
      jb
    }
    jb
  }
}
assert_equal %q{2}, %q{
  def m
    yield 1
  end
  m{|ib|
    ib*2
  }
}
assert_equal %q{92580}, %q{
  def m
    yield 12345, 67890
  end
  m{|ib,jb|
    ib*2+jb
  }
}
assert_equal %q{[10, nil]}, %q{
  def iter
    yield 10
  end

  a = nil
  [iter{|a|
    a
  }, a]
}
assert_equal %q{21}, %q{
  def iter
    yield 10
  end

  iter{|a|
    iter{|a|
      a + 1
    } + a
  }
}
assert_equal %q{[10, 20, 30, 40, nil, nil, nil, nil]}, %q{
  def iter
    yield 10, 20, 30, 40
  end

  a = b = c = d = nil
  iter{|a, b, c, d|
    [a, b, c, d]
  } + [a, b, c, d]
}
assert_equal %q{[10, 20, 30, 40, nil, nil]}, %q{
  def iter
    yield 10, 20, 30, 40
  end

  a = b = nil
  iter{|a, b, c, d|
    [a, b, c, d]
  } + [a, b]
}
assert_equal %q{[1]}, %q{
  $a = []
  
  def iter
    yield 1
  end
  
  def m
    x = iter{|x|
      $a << x
      y = 0
    }
  end
  m
  $a
}
assert_equal %q{[1, [2]]}, %q{
  def iter
    yield 1, 2
  end

  iter{|a, *b|
    [a, b]
  }
}
assert_equal %q{[[1, 2]]}, %q{
  def iter
    yield 1, 2
  end

  iter{|*a|
    [a]
  }
}
assert_equal %q{[1, 2, []]}, %q{
  def iter
    yield 1, 2
  end

  iter{|a, b, *c|
    [a, b, c]
  }
}
assert_equal %q{[1, 2, nil, []]}, %q{
  def iter
    yield 1, 2
  end

  iter{|a, b, c, *d|
    [a, b, c, d]
  }
}
assert_equal %q{1}, %q{
  def m
    yield
  end
  m{
    1
  }
}
assert_equal %q{15129}, %q{
  def m
    yield 123
  end
  m{|ib|
    m{|jb|
      ib*jb
    }
  }
}
assert_equal %q{2}, %q{
  def m a
    yield a
  end
  m(1){|ib|
    m(2){|jb|
      ib*jb
    }
  }
}
assert_equal %q{9}, %q{
  sum = 0
  3.times{|ib|
    2.times{|jb|
      sum += ib + jb
    }}
  sum
}
assert_equal %q{10}, %q{
  3.times{|bl|
    break 10
  }
}
assert_equal %q{[1, 2]}, %q{
  def iter
    yield 1,2,3
  end

  iter{|i, j|
    [i, j]
  }
}
assert_equal %q{[1, nil]}, %q{
  def iter
    yield 1
  end

  iter{|i, j|
    [i, j]
  }
}

assert_equal '0', %q{
def m()
end
m {|(v0,*,(*)),|}
m {|(*v0,(*)),|}
m {|(v0,*v1,(*)),|}
m {|((v0,*v1,v2)),|}
m {|(v0,*v1,v2),|}
m {|(v0,*v1,(v2)),|}
m {|((*),*v0,v1),|}
m {|((v0),*v1,v2),|}
m {|(v0,v1,*v2,v3),|}
m {|v0,(v1,*v2,v3),|}
m {|(v0,*v1,v2),v3,|}
m {|(v0,*v1,v2)|}
m {|(v0,*v1,v2),&v3|}
m {|(v0,*v1,v2),*|}
m {|(v0,*v1,v2),*,&v3|}
m {|*,(v0,*v1,v2)|}
m {|*,(v0,*v1,v2),&v3|}
m {|v0,*,(v1,*v2,v3)|}
m {|v0,*,(v1,*v2,v3),&v4|}
m {|(v0,*v1,v2),*,v3|}
m {|(v0,*v1,v2),*,v3,&v4|}
m {|(v0, *v1, v2)|}
m {|(*,v)|}
0
}, "block parameter (shouldn't SEGV: [ruby-dev:31143])"

assert_equal 'nil', %q{
  def m
    yield
  end
  m{|&b| b}.inspect
}, '[ruby-dev:31147]'

assert_equal 'nil', %q{
  def m()
    yield
  end
  m {|(v,(*))|}.inspect
}, '[ruby-dev:31160]'

assert_equal 'nil', %q{
  def m()
    yield
  end
  m {|(*,a,b)|}.inspect
}, '[ruby-dev:31153]'

assert_equal 'nil', %q{
  def m()
    yield
  end
  m {|((*))|}.inspect
}

assert_equal %q{[1, 1, [1, nil], [1, nil], [1, nil], [1, nil], [1, 1], 1, [1, nil], [1, nil], [1, nil], [1, nil], [[1, 1], [1, 1]], [1, 1], [1, 1], [1, 1], [1, nil], [1, nil], [[[1, 1], [1, 1]], [[1, 1], [1, 1]]], [[1, 1], [1, 1]], [[1, 1], [1, 1]], [[1, 1], [1, 1]], [1, 1], [1, 1], [[[[1, 1], [1, 1]], [[1, 1], [1, 1]]], [[[1, 1], [1, 1]], [[1, 1], [1, 1]]]], [[[1, 1], [1, 1]], [[1, 1], [1, 1]]], [[[1, 1], [1, 1]], [[1, 1], [1, 1]]], [[[1, 1], [1, 1]], [[1, 1], [1, 1]]], [[1, 1], [1, 1]], [[1, 1], [1, 1]]]}, %q{
def m(ary = [])
  yield(ary)
end

$ans = []
o = 1
5.times{
  v,(*) = o; $ans << o
  m(o){|(v,(*))| $ans << v}
  ((x, y)) = o; $ans << [x, y]
  m(o){|((x, y))| $ans << [x, y]}
  (((x, y))) = o; $ans << [x, y]
  m(o){|(((x, y)))| $ans << [x, y]}
  o = [o, o]
}; $ans
}

assert_equal '0', %q{
  def m()
    yield [0]
  end
  m {|*,v| v}.inspect
}, '[ruby-dev:31437]'
assert_equal '[0]', %q{
  def m
    yield [0]
  end
  m{|v, &b| v}.inspect
}, '[ruby-dev:31440]'

