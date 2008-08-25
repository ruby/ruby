require 'yarvtest/yarvtest'

class TestBlock < YarvTestBase
  def test_simple
    ae %q(
      def m
        yield
      end
      m{
        1
      }
    )
  end

  def test_param
    ae %q(
      def m
        yield 1
      end
      m{|ib|
        ib*2
      }
    )
    
    ae %q(
      def m
        yield 12345, 67890
      end
      m{|ib,jb|
        ib*2+jb
      }
    )
  end

  def test_param2
    ae %q{
      def iter
        yield 10
      end

      a = nil
      [iter{|a|
        a
      }, a]
    }
    ae %q{
      def iter
        yield 10
      end

      iter{|a|
        iter{|a|
          a + 1
        } + a
      }
    }
    ae %q{
      def iter
        yield 10, 20, 30, 40
      end

      a = b = c = d = nil
      iter{|a, b, c, d|
        [a, b, c, d]
      } + [a, b, c, d]
    }
    ae %q{
      def iter
        yield 10, 20, 30, 40
      end

      a = b = nil
      iter{|a, b, c, d|
        [a, b, c, d]
      } + [a, b]
    }
    ae %q{
      def iter
        yield 10, 20, 30, 40
      end

      a = nil
      iter{|a, $b, @c, d|
        [a, $b]
      } + [a, $b, @c]
    } if false # 1.9 doesn't support expr block parameters
  end

  def test_param3
    if false
      # TODO: Ruby 1.9 doesn't support expr block parameter
      ae %q{
        h = {}
        [1].each{|h[:foo]|}
        h
      }
      ae %q{
        obj = Object.new
        def obj.x=(y)
        $ans = y
      end
      [1].each{|obj.x|}
        $ans
      }
    end
  end

  def test_blocklocal
    ae %q{
      1.times{
        begin
          a = 1
        ensure
          foo = nil
        end
      }
    }
  end

  def test_simplenest
    ae %q(
      def m
        yield 123
      end
      m{|ib|
        m{|jb|
          ib*jb
        }
      }
    )
  end

  def test_simplenest2
    ae %q(
      def m a
        yield a
      end
      m(1){|ib|
        m(2){|jb|
          ib*jb
        }
      }
    )
  end

  def test_nest2
    ae %q(
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
    )

    ae %q(
      def m
        yield 1
      end
      
      m{|ib|
        m{|jb|
          i = 20
        }
      }
    )

    ae %q(
      def m
        yield 1
      end
      
      m{|ib|
        m{|jb|
          ib = 20
          kb = 2
        }
      }
    )

    ae %q(
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
    )
    
    ae %q(
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
    )
  end

  def test_ifunc
    ae %q{
      (1..3).to_a
    }

    ae %q{
      (1..3).map{|e|
        e * 4
      }
    }

    ae %q{
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

    ae %q{
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
  end

  def test_times
    ae %q{
      sum = 0
      3.times{|ib|
        2.times{|jb|
          sum += ib + jb
        }}
      sum
    }
    ae %q{
      3.times{|bl|
        break 10
      }
    }
  end

  def test_for
    ae %q{
      sum = 0
      for x in [1, 2, 3]
        sum += x
      end
      sum
    }
    ae %q{
      sum = 0
      for x in (1..5)
        sum += x
      end
      sum
    }
    ae %q{
      sum = 0
      for x in []
        sum += x
      end
      sum
    }
    ae %q{
      ans = []
      1.times{
        for n in 1..3
          a = n
          ans << a
        end
      }
    }
    ae %q{
      ans = []
      for m in 1..3
        for n in 1..3
          a = [m, n]
          ans << a
        end
      end
    }
  end
  
  def test_unmatched_params
    ae %q{
      def iter
        yield 1,2,3
      end

      iter{|i, j|
        [i, j]
      }
    }
    ae %q{
      def iter
        yield 1
      end

      iter{|i, j|
        [i, j]
      }
    }
  end

  def test_rest
    # TODO: known bug
    #ae %q{
    #  def iter
    #    yield 1, 2
    #  end
    #
    #  iter{|a, |
    #    [a]
    #  }
    #}
    ae %q{
      def iter
        yield 1, 2
      end

      iter{|a, *b|
        [a, b]
      }
    }
    ae %q{
      def iter
        yield 1, 2
      end

      iter{|*a|
        [a]
      }
    }
    ae %q{
      def iter
        yield 1, 2
      end

      iter{|a, b, *c|
        [a, b, c]
      }
    }
    ae %q{
      def iter
        yield 1, 2
      end

      iter{|a, b, c, *d|
        [a, b, c, d]
      }
    }
  end

  def test_param_and_locals
    ae %q{
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
  end

  def test_c_break
    ae %q{
      [1,2,3].find{|x| x == 2}
    }
    ae %q{
      class E
        include Enumerable
        def each(&block)
          [1, 2, 3].each(&block)
        end
      end
      E.new.find {|x| x == 2 }
    }
  end
end
