require 'yarvtest/yarvtest'

class TestEval < YarvTestBase
  def test_eval
    ae %q{
      eval('1')
    }
    ae %q{
      eval('a=1; a')
    }
    ae %q{
      a = 1
      eval('a')
    }
  end

  def test_eval_with_send
    ae %q{
      __send__ :eval, %{
        :ok
      }
    }
    ae %q{
      1.__send__ :instance_eval, %{
        :ok
      }
    }
  end

  def test_module_eval
    ae %q{
      Const = :top
      class C
        Const = :C
      end
      C.module_eval{
        Const
      }
    }
    ae %q{
      Const = :top
      class C
        Const = :C
      end
      C.module_eval %{
        Const
      }
    } if false # TODO: Ruby 1.9 error

    ae %q{
      Const = :top
      class C
        Const = :C
      end
      C.class_eval %{
        def m
          Const
        end
      }
      C.new.m
    }
    ae %q{
      Const = :top
      class C
        Const = :C
      end
      C.class_eval{
        def m
          Const
        end
      }
      C.new.m
    }
  end

  def test_instance_eval
    ae %q{
      1.instance_eval{
        self
      }
    }
    ae %q{
      'foo'.instance_eval{
        self
      }
    }
    ae %q{
      class Fixnum
        Const = 1
      end
      1.instance_eval %{
        Const
      }
    }
  end
  
  def test_nest_eval
    ae %q{
      Const = :top
      class C
        Const = :C
      end
      $nest = false
      $ans = []
      def m
        $ans << Const
        C.module_eval %{
          $ans << Const
          Boo = false unless defined? Boo
          unless $nest
            $nest = true
            m
          end
        }
      end
      m
      $ans
    }
    ae %q{
      $nested = false
      $ans = []
      $pr = proc{
        $ans << self
        unless $nested
          $nested = true
          $pr.call
        end
      }
      class C
        def initialize &b
          10.instance_eval(&b)
        end
      end
      C.new(&$pr)
      $ans
    }
  end

  def test_binding
    ae %q{
      def m
        a = :ok
        $b = binding
      end
      m
      eval('a', $b)
    }
    ae %q{
      def m
        a = :ok
        $b = binding
      end
      m
      eval('b = :ok2', $b)
      eval('[a, b]', $b)
    }
    ae %q{
      $ans = []
      def m
        $b = binding
      end
      m
      $ans << eval(%q{
        $ans << eval(%q{
          a
        }, $b)
        a = 1
      }, $b)
      $ans
    }
    ae %q{
      Const = :top
      class C
        Const = :C
        def m
          binding
        end
      end
      eval('Const', C.new.m)
    }
    ae %q{
      Const = :top
      a = 1
      class C
        Const = :C
        def m
          eval('Const', TOPLEVEL_BINDING)
        end
      end
      C.new.m
    }
    ae %q{
      class C
        $b = binding
      end
      eval %q{
        def m
          :ok
        end
      }, $b
      p C.new.m
    }
    ae %q{
      b = proc{
        a = :ok
        binding
      }.call
      a = :ng
      eval("a", b)
    }
    ae %q{
      class C
        def foo
          binding
        end
      end
      C.new.foo.eval("self.class.to_s")
    }
  end
end

