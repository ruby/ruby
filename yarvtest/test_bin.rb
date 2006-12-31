require 'yarvtest/yarvtest'

# test of basic instruction
class TestBIN < YarvTestBase
  
  def test_literal
    ae %q(true)
    ae %q(false)
    ae %q(nil)
    ae %q(1234)
    ae %q(:sym)
    ae %q(123456789012345678901234567890)
    ae %q(1.234)
    ae %q(0x12)
    ae %q(0b0101001)
    ae %q(1_2_3)   # 123
  end

  def test_self
    ae %q(self)
  end
  
  def test_string
    ae %q('str')
  end

  def test_dstring
    ae %q(
      "1+1 = #{1+1}"
    )
    ae %q{
      i = 10
      "#{i} ** #{i} = #{i ** i}"
    }
    ae %q{
      s = "str"
      s.__id__ == "#{s}".__id__
    }
  end

  def test_dsym
    ae %q{
      :"a#{1+2}c"
    }
  end
  
  def test_xstr
    ae %q(`echo hoge`)
    ae %q(hoge = 'huga'; `echo #{hoge}`)
  end
  
  def test_regexp
    ae %q{
      /test/ =~ 'test'
    }
    ae %q{
      /test/ =~ 'tes'
    }
    ae %q{
      r = /test/; l = 'test'
      r =~ l
    }
    ae %q{
      r = /testx/; l = 'test'
      r =~ l
    }
    ae %q{
      i = 10
      /test#{i}/ =~ 'test10'
    }
    ae %q{
      i = 10
      /test#{i}/ =~ 'test20'
    }
    ae %q{
      :sym =~ /sym/
    }
    ae %q{
      sym = :sym
      sym =~ /sym/
    }
    ae %q{
      reg = /sym/
      :sym =~ reg
    }
  end

  def test_array
    ae %q([])
    ae %q([1,2,3])
    ae %q([1+1,2+2,3+3])
    ae %q([0][0]+=3)
    ae %q([0][0]-=3)
  end

  def test_array_access
    ae %q(ary = [1,2,3]; ary[1])
    ae %q(ary = [1,2,3]; ary[1] = 10)
    ae %q(ary = Array.new(10, 100); ary[3])
  end
  
  def test_hash
    ae %q({})
    ae %q({1 => 2})
    ae %q({"str" => "val", "str2" => "valval"})
    ae %q({1 => 2, 1=>3})
  end

  def test_range
    ae %q((1..2))
    ae %q((1...2))
    ae %q(((1+1)..(2+2)))
    ae %q(((1+1)...(2+2)))
  end
  
  def test_not
    ae %q(!true)
    ae %q(!nil)
    ae %q(!false)
    ae %q(!(1+1))
    ae %q(!!nil)
    ae %q(!!1)
  end

  # var
  def test_local
    ae %q(a = 1)
    ae %q(a = 1; b = 2; a)
    ae %q(a = b = 3)
    ae %q(a = b = 3; a)
    ae %q(a = b = c = 4)
    ae %q(a = b = c = 4; c)
  end

  def test_constant
    ae %q(C = 1; C)
    ae %q(C = 1; $a = []; 2.times{$a << ::C}; $a)
    ae %q(
      class A
        class B
          class C
            Const = 1
          end
        end
      end
      (1..2).map{
        A::B::C::Const
      }
    ) do
      remove_const :A
    end
    
    ae %q(
      class A
        class B
          Const = 1
          class C
            (1..2).map{
              Const
            }
          end
        end
      end
    ) do
      remove_const :A
    end
    
    ae %q(
      class A
        Const = 1
        class B
          class C
            (1..2).map{
              Const
            }
          end
        end
      end
    ) do
      remove_const :A
    end
    
    ae %q(
      Const = 1
      class A
        class B
          class C
            (1..2).map{
              Const
            }
          end
        end
      end
    ) do
      remove_const :A
      remove_const :Const
    end

    ae %q{
      C = 1
      begin
        C::D
      rescue TypeError
        :ok
      else
        :ng
      end
    }
  end

  def test_constant2
    ae %q{
      class A
        class B
          C = 10
        end
      end
      i = 0
      while i<3
        i+=1
        r = A::B::C
      end
      r
    } do
      remove_const :A
    end
    
    ae %q{
      class A
        class B
          C = 10
        end
      end
      i = 0
      while i<3
        i+=1
        r = A::B::C
        class A::B
          remove_const :C
        end
        A::B::C = i**i
      end
      r
    } do
      remove_const :A
    end
    
    ae %q{
      class C
        Const = 1
        (1..3).map{
          self::Const
        }
      end
    }
    ae %q{
      class C
        Const = 1
        (1..3).map{
          eval('self')::Const
        }
      end
    }
    ae %q{
      class C
        Const = 0
        def self.foo()
          self::Const
        end
      end
      
      class D < C
        Const = 1
      end
      
      class E < C
        Const = 2
      end
 
      [C.foo, D.foo, E.foo]
    }
  end
  
  def test_gvar
    ae %q(
      $g1 = 1
    )

    ae %q(
      $g2 = 2
      $g2
    )
  end

  def test_cvar
    ae %q{
      class C
        @@c = 1
        def m
          @@c += 1
        end
      end

      C.new.m
    } do
      remove_const :C
    end
  end

  def test_cvar_from_singleton
    ae %q{
      class C
        @@c=1
        class << self
          def m
            @@c += 1
          end
        end
      end
      C.m
    } do
      remove_const :C
    end
  end

  def test_cvar_from_singleton2
    ae %q{
      class C
        @@c = 1
        def self.m
          @@c += 1
        end
      end
      C.m
    } do
      remove_const :C
    end
  end
  
  def test_op_asgin2
    ae %q{
      class C
        attr_accessor :a
      end
      r = []
      o = C.new
      o.a &&= 1
      r << o.a
      o.a ||= 2
      r << o.a
      o.a &&= 3
      r << o.a
      r
    } do
      remove_const :C
    end
    ae %q{
      @@x ||= 1
    }
    ae %q{
      @@x = 0
      @@x ||= 1
    }
  end

  def test_op_assgin_and_or
    ae %q{
      r = []
      a = 1  ; a ||= 2; r << a
      a = nil; a ||= 2; r << a
      a = 1  ; a &&= 2; r << a
      a = nil; a &&= 2; r << a
      r
    }
    ae %q{
      a = {}
      a[0] ||= 1
    }
    ae %q{
      a = {}
      a[0] &&= 1
    }
    ae %q{
      a = {0 => 10}
      a[0] ||= 1
    }
    ae %q{
      a = {0 => 10}
      a[0] &&= 1
    }
  end
  
  def test_backref
    ae %q{
      /a(b)(c)d/ =~ 'xyzabcdefgabcdefg'
      [$1, $2, $3, $~.class, $&, $`, $', $+]
    }
    
    ae %q{
      def m
        /a(b)(c)d/ =~ 'xyzabcdefgabcdefg'
        [$1, $2, $3, $~.class, $&, $`, $', $+]
      end
      m
    }
  end

  def test_fact
    ae %q{
      def fact(n)
        if(n > 1)
          n * fact(n-1)
        else
          1
        end
      end
      fact(300)
    }
  end

  def test_mul
    ae %q{
      2*0
    }
    ae %q{
      0*2
    }
    ae %q{
      2*2
    }
  end

  def test_div
    ae %q{
      3/2
    }
    ae %q{
      3.0/2.0
    }
    ae %q{
      class C
        def /(a)
          a * 100
        end
      end
      C.new/3
    } do
      remove_const :C
    end
  end

  def test_length
    ae %q{
      [].length
    }
    ae %q{
      [1, 2].length
    }
    ae %q{
      {}.length
    }
    ae %q{
      {:a => 1, :b => 2}.length
    }
    ae %q{
      class C
        def length
          'hoge'
        end
      end
      C.new.length
    } do
      remove_const :C
    end
  end

  def test_mod
    ae %q{
      3%2
    }
    ae %q{
      3.0%2.0
    }
    ae %q{
      class C
        def % (a)
          a * 100
        end
      end
      C.new%3
    } do
      remove_const :C
    end
  end

  def test_attr_set
    ae %q{
      o = Object.new
      def o.[]=(*args)
        args
      end
      [o[]=:x, o[0]=:x, o[0, 1]=:x, o[0, 1, 2]=:x]
    }
    ae %q{
      o = Object.new
      def o.foo=(*args)
        args
      end
      o.foo = :x
    }
    ae %q{
      $r = []
      class C
        def [](*args)
          $r << [:ref, args]
          args.size
        end
        
        def []=(*args)
          $r << [:set, args]
          args.size
        end
      end
      
      o = C.new
      ary = [:x, :y]
      o[1] = 2
      o[1, 2] = 3
      o[1, 2, *ary] = 3
      o[1, 2, *ary, 3] = 4
      $r
    }
  end
  
  def test_aref_aset
    ae %q{
      a = []
      a << 0
      a[1] = 1
      a[2] = 2
      a[3] = a[1] + a[2]
    }
    ae %q{
      a = {}
      a[1] = 1
      a[2] = 2
      a[3] = a[1] + a[2]
      a.sort
    }
    ae %q{
      class C
        attr_reader :a, :b
        def [](a)
          @a = a
        end

        def []=(a, b)
          @b = [a, b]
        end
      end
      c = C.new
      c[3]
      c[4] = 5
      [c.a, c.b]
    } do
      remove_const :C
    end
  end

  def test_array_concat
    ae %q{
      ary = []
      [:x, *ary]
    }
    #ae %q{
    #  ary = 1
    #  [:x, *ary]
    #}
    ae %q{
      ary = [1, 2]
      [:x, *ary]
    }
  end
end

