require 'yarvtest/yarvtest'

class TestClass < YarvTestBase

  def test_simple
    ae %q(
      class C
        def m(a,b)
          a+b
        end
      end
      C.new.m(1,2)
    ) do
      remove_const(:C)
    end

    ae %q(
      class A
      end
      class A::B
        def m
          A::B.name
        end
      end
      A::B.new.m
    ) do
      remove_const(:A)
    end

    #ae %q(
    #  class (class C;self; end)::D < C
    #    self.name
    #  end
    #) do
    #  remove_const(:C)
    #end
    
  end
  
  def test_sub
    ae %q(
      class A
        def m
          123
        end
      end
      
      class B < A
      end
      
      B.new.m
    ) do
      remove_const(:A)
      remove_const(:B)
    end
    
    ae %q(
      class A
        class B
          class C
            def m
              456
            end
          end
        end
      end
      
      class A::BB < A::B::C
      end
      
      A::BB.new.m
    ) do
      remove_const(:A)
    end
  end

  def test_attr
    ae %q(
      class C
        def set
          @a = 1
        end
        def get
          @a
        end
      end
      c = C.new
      c.set
      c.get
    ) do
      remove_const(:C)
    end
  end

  def test_initialize
    ae %q{
      class C
        def initialize
          @a = :C
        end
        def a
          @a
        end
      end
      
      C.new.a
    } do
      remove_const(:C)
    end
  end

  def test_to_s
    ae %q{
      class C
        def to_s
          "hoge"
        end
      end
      
      "ab#{C.new}cd"
    } do
      remove_const(:C)
    end
    
  end

  def test_attr_accessor
    ae %q{
      class C
        attr_accessor :a
        attr_reader   :b
        attr_writer   :c
        def b_write
          @b = 'huga'
        end
        def m a
          'test_attr_accessor' + @b + @c
        end
      end

      c = C.new
      c.a = true
      c.c = 'hoge'
      c.b_write
      c.m(c.b)
    } do
      remove_const(:C)
    end
  end

  def test_super
    ae %q{
      class C
        def m1
          100
        end
        
        def m2 a
          a + 100
        end
      end
      
      class CC < C
        def m1
          super() * 100
        end
        
        def m2
          super(200) * 100
        end
      end

      a = CC.new
      a.m1 + a.m2
    } do
      remove_const(:C)
      remove_const(:CC)
    end
  end

  def test_super2
    ae %q{
      class C
        def m(a, b)
          a+b
        end
      end

      class D < C
        def m arg
          super(*arg) + super(1, arg.shift)
        end
      end

      D.new.m([1, 2])
    }
    
    ae %q{
      class C
        def m
          yield
        end
      end
      
      class D < C
        def m
          super(){
            :D
          }
        end
      end

      D.new.m{
        :top
      }
    }
    ae %q{
      class C0
        def m a, &b
          [a, b]
        end
      end
      
      class C1 < C0
        def m a, &b
          super a, &b
        end
      end
      
      C1.new.m(10)
    }
  end

  def test_zsuper_from_define_method
    ae %q{
      class C
        def a
          "C#a"
        end
        def m
          "C#m"
        end
      end
      class D < C
        define_method(:m){
          super
        }
        define_method(:a){
          r = nil
          1.times{
            r = super
          }
          r
        }
      end
      D.new.m + D.new.a
    }
    ae %q{
      class X
        def a
          "X#a"
        end
        def b
          class << self
            define_method(:a) {
              super
            }
          end
        end
      end
      
      x = X.new
      x.b
      x.a
    }
    ae %q{
      class C
        def m arg
          "C#m(#{arg})"
        end
        def b
          class << self
            define_method(:m){|a|
              super
            }
          end
          self
        end
      end
      C.new.b.m(:ok)
    }
    ae %q{
      class C
        def m *args
          "C#m(#{args.join(', ')})"
        end
        def b
          class << self
            define_method(:m){|a, b|
              r = nil
              1.times{
                r = super
              }
              r
            }
          end
          self
        end
      end
      C.new.b.m(:ok1, :ok2)
    } if false # ruby 1.9 dumped core
    ae %q{ # [yarv-dev:859]
      $ans = []
      class A
        def m_a
          $ans << "m_a"
        end
        def def_m_a
          $ans << "def_m_a"
        end
      end
      class B < A
        def def_m_a
          B.class_eval{
            super
            define_method(:m_a) do
              super
            end
          }
          super
        end
      end
      b = B.new
      b.def_m_a
      b.m_a
      $ans
    }
    ae %q{
      class A
        def hoge
          :hoge
        end
        def foo
          :foo
        end
      end
      class B < A
        def memoize(name)
          B.instance_eval do
            define_method(name) do
              [name, super]
            end
          end
        end
      end
      b = B.new
      b.memoize(:hoge)
      b.memoize(:foo)
      [b.foo, b.hoge]
    }
  end
  
  def test_zsuper
    ae %q{
      class C
        def m1
          100
        end
        
        def m2 a
          a + 100
        end

        def m3 a
          a + 200
        end
      end
      
      class CC < C
        def m1
          super * 100
        end
        
        def m2 a
          super  * 100
        end

        def m3 a
          a = 400
          super * 100
        end
      end

      a = CC.new
      a.m1 + a.m2(200) + a.m3(300)
    } do
      remove_const(:C)
      remove_const(:CC)
    end
  end

  def test_zsuper2
    ae %q{
      class C1
        def m
          10
        end
      end

      class C2 < C1
        def m
          20 + super
        end
      end
      
      class C3 < C2
        def m
          30 + super
        end
      end
      
      C3.new.m
    } do
      remove_const(:C1)
      remove_const(:C2)
      remove_const(:C3)
    end

    ae %q{
      class C
        def m
          yield
        end
      end
      
      class D < C
        def m
          super{
            :D
          }
        end
      end

      D.new.m{
        :top
      }
    }
    ae %q{
      class C
        def m(a, b, c, d)
          a+b+c+d
        end
      end

      class D < C
        def m(a, b=1, c=2, *d)
          d[0] ||= 0.1
          [super,
            begin
              a *= 2
              b *= 3
              c *= 4
              d[0] *= 5
              super
            end
          ]
        end
      end
      ary = []
      ary << D.new.m(10, 20, 30, 40)
      if false # On current ruby, these programs don't work
        ary << D.new.m(10, 20, 30)
        ary << D.new.m(10, 20)
        ary << D.new.m(10)
      end
      ary
    }
    ae %q{
      class C
        def m(a, b, c, d)
          a+b+c+d
        end
      end

      class D < C
        def m(a, b=1, c=2, d=3)
          [super,
            begin
              a *= 2
              b *= 3
              c *= 4
              d *= 5
              super
            end
          ]
        end
      end
      ary = []
      ary << D.new.m(10, 20, 30, 40)
      ary << D.new.m(10, 20, 30)
      ary << D.new.m(10, 20)
      ary << D.new.m(10)
      ary
    }
    ae %q{
      class C
        def m(a, b, c, d, &e)
          a+b+c+d+e.call
        end
        def n(a, b, c, d, &e)
          a+b+c+d+e.call
        end
      end

      class D < C
        def m(a, b=1, c=2, *d, &e)
          super
        end
        def n(a, b=1, c=2, d=3, &e)
          super
        end
      end
      ary = []
      ary << D.new.m(1, 2, 3, 4){
        5
      }
      ary << D.new.m(1, 2, 3, 4, &lambda{
        5
      })
      ary << D.new.n(1, 2, 3){
        5
      }
      ary << D.new.n(1, 2){
        5
      }
      ary << D.new.n(1){
        5
      }
      ary
    }
  end

  def test_super_with_private
    ae %q{
      class C
        private
        def m1
          :OK
        end
        protected
        def m2
        end
      end
      class D < C
        def m1
          [super, super()]
        end
        def m2
          [super, super()]
        end
      end
      D.new.m1 + D.new.m2
    }
  end

  def test_const_in_other_scope
    ae %q{
      class C
        Const = :ok
        def m
          1.times{
            Const
          }
        end
      end
      C.new.m
    } do
      remove_const(:C)
    end

    ae %q{
      class C
        Const = 1
        def m
          begin
            raise
          rescue
            Const
          end
        end
      end
      C.new.m
    } do
      remove_const(:C)
    end
  end

  def test_reopen_not_class
    ae %q{ # [yarv-dev:782]
      begin
        B = 1
        class B
          p B
        end
      rescue TypeError => e
        e.message
      end
    }
    ae %q{ # [yarv-dev:800]
      begin
        B = 1
        module B
          p B
        end
      rescue TypeError => e
        e.message
      end
    }
  end

  def test_set_const_not_class
    ae %q{ 
      begin
        1::A = 1
      rescue TypeError => e
        e.message
      end
    }
  end

  def test_singletonclass
    ae %q{
      obj = ''
      class << obj
        def m
          :OK
        end
      end
      obj.m
    }
    ae %q{
      obj = ''
      Const = :NG
      class << obj
        Const = :OK
        def m
          Const
        end
      end
      obj.m
    }
    ae %q{
      obj = ''
      class C
        def m
          :NG
        end
      end
      class << obj
        class C
          def m
            :OK
          end
        end
        def m
          C.new.m
        end
      end
      obj.m
    }
    ae %q{ # [yarv-dev:818]
      class A
      end
      class << A
        C = "OK"
        def m
          class << Object
            $a = C
          end
        end
      end
      A.m
      $a
    }
  end

  def test_include
    ae %q{
      module M
        class A
          def hoge
            "hoge"
          end
        end
      end
      
      class A
        include M
        def m
          [Module.nesting, A.new.hoge, instance_eval("A.new.hoge")]
        end
      end
      A.new.m
    }
  end

  def test_colon3
    ae %q{
      class A
        ::B = :OK
      end
      B
    }
    ae %q{
      class A
        class ::C
        end
      end
      C
    }
  end

  def test_undef
    # [yarv-dev:999]
    ae %q{
      class Parent
        def foo
        end
      end
      class Child < Parent
        def bar
        end
        
        undef foo, bar
      end
      
      c = Child.new
      [c.methods.include?('foo'),  c.methods.include?('bar')]
    }
  end

  def test_dup
    ae %q{
      ObjectSpace.each_object{|obj|
        if Module === obj && (obj.respond_to? :dup)
          obj.dup
        end
      }
      :ok
    }
  end

  def test_ivar2
    ae %q{
      class C
        def initialize
          @_v = 1
        end
        
        def foo
          @_v
        end
      end
      class D < C
        def initialize
          @_v = 2
          super
        end
        def foo
          [@_v, super]
        end
      end
      D.new.foo
    }
    ae %q{
      class C
        def initialize
          @_c = 1
        end
      end

      class D < C
        def initialize
          super
          @_d = 2
        end
      end

      D.new.instance_variables
    }
  end
end

