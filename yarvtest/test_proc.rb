require 'yarvtest/yarvtest'

class TestProc < YarvTestBase
  def test_simpleproc
    ae %q{
      def m(&b)
        b
      end
      m{1}.call
    }

    ae %q{
      def m(&b)
        b
      end

      m{
        a = 1
        a + 2
      }.call
    }
  end

  def test_procarg
    ae %q{
      def m(&b)
        b
      end

      m{|e_proctest| e_proctest}.call(1)
    }

    ae %q{
      def m(&b)
        b
      end

      m{|e_proctest1, e_proctest2|
        a = e_proctest1 * e_proctest2 * 2
        a * 3
      }.call(1, 2)
    }

    ae %q{
      [
      Proc.new{|*args| args}.call(),
      Proc.new{|*args| args}.call(1),
      Proc.new{|*args| args}.call(1, 2),
      Proc.new{|*args| args}.call(1, 2, 3),
      ]
    }
    ae %q{
      [
      Proc.new{|a, *b| [a, b]}.call(),
      Proc.new{|a, *b| [a, b]}.call(1),
      Proc.new{|a, *b| [a, b]}.call(1, 2),
      Proc.new{|a, *b| [a, b]}.call(1, 2, 3),
      ]
    }
  end

  def test_closure
    ae %q{
      def make_proc(&b)
        b
      end
      
      def make_closure
        a = 0
        make_proc{
          a+=1
        }
      end
      
      cl = make_closure
      cl.call + cl.call * cl.call
    }
  end

  def test_nestproc2
    ae %q{
      def iter
        yield
      end
      
      def getproc &b
        b
      end
      
      iter{
        bvar = 3
        getproc{
          bvar2 = 4
          bvar * bvar2
        }
      }.call
    }

    ae %q{
      def iter
        yield
      end
      
      def getproc &b
        b
      end
      
      loc1 = 0
      pr1 = iter{
        bl1 = 1
        getproc{
          loc1 += 1
          bl1  += 1
          loc1 + bl1
        }
      }
      
      pr2 = iter{
        bl1 = 1
        getproc{
          loc1 += 1
          bl1  += 1
          loc1 + bl1
        }
      }
      
      pr1.call; pr2.call
      pr1.call; pr2.call
      pr1.call; pr2.call
      (pr1.call + pr2.call) * loc1
    }
  end

  def test_proc_with_cref
    ae %q{
      Const = :top
      class C
        Const = :C
        $pr = proc{
          (1..2).map{
            Const
          }
        }
      end
      $pr.call
    }
    ae %q{
      Const = :top
      class C
        Const = :C
      end
      pr = proc{
        Const
      }
      C.class_eval %q{
        pr.call
      }
    }
  end
  
  def test_3nest
    ae %q{
      def getproc &b
        b
      end
      
      def m
        yield
      end
      
      m{
        i = 1
        m{
          j = 2
          m{
            k = 3
            getproc{
              [i, j, k]
            }
          }
        }
      }.call
    }
  end

  def test_nestproc1
    ae %q{
      def proc &b
        b
      end
      
      pr = []
      proc{|i_b|
        p3 = proc{|j_b|
          pr << proc{|k_b|
            [i_b, j_b, k_b]
          }
        }
        p3.call(1)
        p3.call(2)
      }.call(0)
      
      pr[0].call(:last).concat pr[1].call(:last)
    }
  end

  def test_proc_with_block
    ae %q{
      def proc(&pr)
        pr
      end
      
      def m
        a = 1
        m2{
          a
        }
      end
      
      def m2
        b = 2
        proc{
          [yield, b]
        }
      end
      
      pr = m
      x = ['a', 1,2,3,4,5,6,7,8,9,0,
                1,2,3,4,5,6,7,8,9,0,
                1,2,3,4,5,6,7,8,9,0,
                1,2,3,4,5,6,7,8,9,0,
                1,2,3,4,5,6,7,8,9,0,]
      pr.call
    }
    ae %q{
      def proc(&pr)
        pr
      end
      
      def m
        a = 1
        m2{
          a
        }
      end
      
      def m2
        b = 2
        proc{
          [yield, b]
        }
        100000.times{|x|
          "#{x}"
        }
        yield
      end
      m
    }
  end

  def test_method_to_proc
    ae %q{
      class C
        def foo
          :ok
        end
      end
      
      def block
        C.method(:new).to_proc
      end
      b = block()
      b.call.foo
    }
  end

  def test_safe
    ae %q{
      pr = proc{
        $SAFE
      }
      $SAFE = 1
      pr.call
    }
    ae %q{
      pr = proc{
        $SAFE += 1
      }
      [pr.call, $SAFE]
    }
  end
end

