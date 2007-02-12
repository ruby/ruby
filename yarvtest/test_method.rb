require 'yarvtest/yarvtest'
class TestMethod < YarvTestBase
  
  def test_simple_method
    ae %q{
      def m_simple_method
        1
      end
      m_simple_method()
    }
  end

  def test_polymorphic
    ae %q{
      o1 = 'str'
      o2 = 1
      str = ''
      i = 1
      while i<10
        i+=1
        o = (i%2==0) ? o1 : o2
        str += o.to_s
      end
      str
    }
  end

  def test_arg
    ae <<-'EOS'
    def m_arg(a1, a2)
      a1+a2
    end
    m_arg(1,2)
    EOS
  end

  def test_rec
    ae <<-'EOS'
    def m_rec n
      if n > 1
        n + m_rec(n-1)
      else
        1
      end
    end
    m_rec(10)
    EOS
  end

  def test_splat
    ae %q{
      def m a
        a
      end
      begin
        m(*1)
      rescue TypeError
        :ok
      end
    }
    ae %q{
      def m a, b
        [a, b]
      end
      m(*[1,2])
    }
    ae %q{
      def m a, b, c
        [a, b, c]
      end
      m(1, *[2, 3])
    }

    ae %q{
      def m a, b, c
        [a, b, c]
      end

      m(1, 2, *[3])
    }
  end

  def test_rest
    ae %q{
      def m *a
        a
      end

      m
    }

    ae %q{
      def m *a
        a
      end

      m 1
    }

    ae %q{
      def m *a
        a
      end

      m 1, 2, 3
    }

    ae %q{
      def m x, *a
        [x, a]
      end

      m 1
    }

    ae %q{
      def m x, *a
        [x, a]
      end

      m 1, 2
    }

    ae %q{
      def m x, *a
        [x, a]
      end

      m 1, 2, 3, 4
    }
  end

  def test_opt
    ae %q{
      def m a=1
        a
      end
      m
    }
    ae %q{
      def m a=1
        a
      end
      m 2
    }
    ae %q{
      def m a=1, b=2
        [a, b]
      end
      m
    }
    ae %q{
      def m a=1, b=2
        [a, b]
      end
      m 10
    }
    ae %q{
      def m a=1, b=2
        [a, b]
      end
      m 10, 20
    }
    ae %q{
      def m x, a=1, b=2
        [x, a, b]
      end
      m 10
    }
    ae %q{
      def m x, a=1, b=2
        [x, a, b]
      end
      m 10, 20
    }
    ae %q{
      def m x, a=1, b=2
        [x, a, b]
      end
      m 10, 20, 30
    }
    ae %q{
      def m x, y, a
        [x, y, a]
      end
      m 10, 20, 30
    }
  end


  def test_opt_rest
    ae %q{
      def m0 b = 0, c = 1, *d
        [:sep, b, c, d]
      end
      
      def m1 a, b = 0, c = 1, *d
        [:sep, a, b, c, d]
      end
      
      def m2 x, a, b = 0, c = 1, *d
        [:sep, x, a, b, c, d]
      end

      def m3 x, y, a, b = 0, c = 1, *d
        [:sep, x, y, a, b, c, d]
      end

      def s3 x, y, a, b = 0, c = 1
        [:sep, x, y, a, b, c]
      end
      
      m0() +
      m0(:a) +
      m0(:a, :b) +
      m0(:a, :b, :c) +
      m0(:a, :b, :c, :d) +
      m0(:a, :b, :c, :d, :e) +
      m1(:a) +
      m1(:a, :b) +
      m1(:a, :b, :c) +
      m1(:a, :b, :c, :d) +
      m1(:a, :b, :c, :d, :e) +
      m2(:a, :b) +
      m2(:a, :b, :c) +
      m2(:a, :b, :c, :d) +
      m2(:a, :b, :c, :d, :e) +
      m2(:a, :b, :c, :d, :e, :f) +
      m3(:a, :b, :c) +
      m3(:a, :b, :c, :d) +
      m3(:a, :b, :c, :d, :e) +
      m3(:a, :b, :c, :d, :e, :f) +
      m3(:a, :b, :c, :d, :e, :f, :g)
    }
  end

  def test_opt_rest_block
    ae %q{
      def m a, b = 0, c = 1, *d, &pr
        [a, b, c, d, pr]
      end
      m(:a) +
      m(:a, :b) +
      m(:a, :b, :c) +
      m(:a, :b, :c, :d) +
      m(:a, :b, :c, :d, :e)
    }
    ae %q{
      def m a, b = 0, c = 1, *d, &pr
        [a, b, c, d, pr.call]
      end
      
      m(:a){1} +
      m(:a, :b){2} +
      m(:a, :b, :c){3} +
      m(:a, :b, :c, :d){4} +
      m(:a, :b, :c, :d, :e){5}
    }
  end

  def test_singletonmethod
    ae %q{
      lobj = Object.new
      def lobj.m
        :singleton
      end
      lobj.m
    }
    ae %q{
      class C
        def m
          :C_m
        end
      end
      lobj = C.new
      def lobj.m
        :Singleton_m
      end
      lobj.m
    }
  end
  
  def test_singletonmethod_with_const
    ae %q{
      class C
        Const = :C
        def self.m
          1.times{
            Const
          }
        end
      end
      C.m
    }
  end
  
  def test_alias
    ae %q{
      def m1
        :ok
      end
      alias :m2 :m1
      m1
    }
    ae %q{
      def m1
        :ok
      end
      alias m2 m1
      m1
    }
    ae %q{
      def m1
        :ok
      end
      alias m2 :m1
      m1
    }
    ae %q{
      def m1
        :ok
      end
      alias :m2 m1
      m1
    }
    ae %q{
      def m1
        :ok
      end
      alias m2 m1
      def m1
        :ok2
      end
      [m1, m2]
    }
  end

  def test_split
    ae %q{
      'abc'.split(/b/)
    }
    ae %q{
      1.times{|bi|
        'abc'.split(/b/)
      }
    }
  end

  def test_block_pass
    ae %q{
      def getproc &b
        b
      end
      def m
        yield
      end
      m(&getproc{
        "test"
      })
    }
    ae %q{
      def getproc &b
        b
      end
      def m a
        yield a
      end
      m(123, &getproc{|block_a|
        block_a
      })
    }
    ae %q{
      def getproc &b
        b
      end
      def m *a
        yield a
      end
      m(123, 456, &getproc{|block_a|
        block_a
      })
    }
    ae %q{
      def getproc &b
        b
      end
      [1,2,3].map(&getproc{|block_e| block_e*block_e})
    }
    ae %q{
      def m a, b, &c
        c.call(a, b)
      end
      m(10, 20){|x, y|
        [x+y, x*y]
      }
    }
    ae %q{
      def m &b
        b
      end
      m(&nil)
    }
    ae %q{
      def m a, &b
        [a, b]
      end
      m(1, &nil)
    }
    ae %q{
      def m a
        [a, block_given?]
      end
      m(1, &nil)
    }
  end

  def test_method_missing
    ae %q{
      class C
        def method_missing id
          id
        end
      end
      C.new.hoge
    } do
      remove_const :C
    end

    ae %q{
      class C
        def method_missing *args, &b
          b.call(args)
        end
      end
      C.new.foo(1){|args|
        args
      }
      C.new.foo(1){|args|
        args
      } +
      C.new.foo(1, 2){|args|
        args
      }
    }
  end

  def test_svar
    ae %q{
      'abc'.match(/a(b)c/)
      $1
    }
  end

  def test_nested_method
    ae %q{
      class A
        def m
          def m2
            p :m2
          end
          m2()
        end
      end
      A.new.m
    }
    ae %q{
      class A
        def m
          def m2
            p :m2
          end
          m2()
        end
      end
      instance_eval('A.new.m')
    }
  end

  def test_private_class_method
    ae %q{
      class C
        def self.m
          :ok
        end
        def self.test
          m
        end
        private_class_method :m
      end
      C.test
    }
  end

  def test_alias_and_private
    ae %q{ # [yarv-dev:899]
      $ans = []
      class C
        def m
          $ans << "OK"
        end
      end
      C.new.m
      class C
        alias mm m
        private :mm
      end
      C.new.m
      begin
        C.new.mm
      rescue NoMethodError
        $ans << "OK!"
      end
      $ans
    }
  end

  def test_break_from_defined_method
    ae %q{
      class C
        define_method(:foo){
          break :ok
        }
      end
      C.new.foo
    }
  end

  def test_return_from_defined_method
    ae %q{
      class C
        define_method(:m){
          return :ok
        }
      end
      C.new.m
    }
  end

  def test_send
    ae %q{
      $r = []
      class C
        def m *args
          $r << "C#m #{args.inspect} #{block_given?}"
        end
      end

      obj = C.new
      obj.send :m
      obj.send :m, :x
      obj.send :m, :x, :y
      obj.send(:m){}
      obj.send(:m, :x){}
      $r
    }
    ae %q{
      class C
        def send
          :ok
        end
      end
      C.new.send
    }
  end

  def test_send_with_private
    ae %q{
      begin
        def m
        end
        self.send :m
      rescue NoMethodError
        :ok
      else
        :ng
      end
    }
    ae %q{
      begin
        def m
        end
        send :m
      rescue NoMethodError
        :ng
      else
        :ok
      end
    }
  end

  def test_funcall
    ae %q{
      $r = []
      def m *args
        $r << "m() #{args.inspect} #{block_given?}"
      end

      funcall :m
      funcall :m, :x
      funcall :m, :x, :y
      funcall(:m){}
      funcall(:m, :x){}
    }
  end
end

