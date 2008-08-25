require 'yarvtest/yarvtest'

# test of syntax
class TestSYNTAX < YarvTestBase

  def test_if_unless
    ae %q(if true  then 1 ; end)
    ae %q(if false then 1 ; end)
    ae %q(if true  then 1 ; else; 2; end)
    ae %q(if false then 1 ; else; 2; end)
    ae %q(if true  then   ; elsif true then ; 1 ; end)
    ae %q(if false then   ; elsif true then ; 1 ; end)

    ae %q(unless true  then 1 ; end)
    ae %q(unless false then 1 ; end)
    ae %q(unless true  then 1 ; else; 2; end)
    ae %q(unless false then 1 ; else; 2; end)

    ae %q(1 if true)
    ae %q(1 if false)
    ae %q(1 if nil)
    
    ae %q(1 unless true)
    ae %q(1 unless false)
    ae %q(1 unless nil)
  end

  def test_while_until
    ae %q(
      i = 0
      while i < 10
        i+=1
      end)

    ae %q(
      i = 0
      while i < 10
        i+=1
      end; i)

    ae %q(
      i = 0
      until i > 10
        i+=1
      end)

    ae %q(
      i = 0
      until i > 10
        i+=1
      end; i)
    # 
    ae %q{
      i = 0
      begin
        i+=1
      end while false
      i
    }
    ae %q{
      i = 0
      begin
        i+=1
      end until true
      i
    }
  end

  def test_and
    ae %q(1 && 2 && 3 && 4)
    ae %q(1 && nil && 3 && 4)
    ae %q(1 && 2 && 3 && nil)
    ae %q(1 && 2 && 3 && false)

    ae %q(1 and 2 and 3 and 4)
    ae %q(1 and nil and 3 and 4)
    ae %q(1 and 2 and 3 and nil)
    ae %q(1 and 2 and 3 and false)
    ae %q(nil && true)
    ae %q(false && true)

  end
  
  def test_or
    ae %q(1 || 2 || 3 || 4)
    ae %q(1 || false || 3 || 4)
    ae %q(nil || 2 || 3 || 4)
    ae %q(false || 2 || 3 || 4)
    ae %q(nil || false || nil || false)

    ae %q(1 or 2 or 3 or 4)
    ae %q(1 or false or 3 or 4)
    ae %q(nil or 2 or 3 or 4)
    ae %q(false or 2 or 3 or 4)
    ae %q(nil or false or nil or false)
  end

  def test_case
    ae %q(
      case 1
      when 2
        :ng
      end)
      
    ae %q(
      case 1
      when 10,20,30
        :ng1
      when 1,2,3
        :ok
      when 100,200,300
        :ng2
      else
        :elseng
      end)
    ae %q(
      case 123
      when 10,20,30
        :ng1
      when 1,2,3
        :ng2
      when 100,200,300
        :ng3
      else
        :elseok
      end
    )
    ae %q(
      case 'test'
      when /testx/
        :ng1
      when /test/
        :ok
      when /tetxx/
        :ng2
      else
        :ng_else
      end
    )
    ae %q(
      case Object.new
      when Object
        :ok
      end
    )
    ae %q(
      case Object
      when Object.new
        :ng
      else
        :ok
      end
    )
    ae %q{
      case 'test'
      when 'tes'
        :ng
      when 'te'
        :ng
      else
        :ok
      end
    }
    ae %q{
      case 'test'
      when 'tes'
        :ng
      when 'te'
        :ng
      when 'test'
        :ok
      end
    }
    ae %q{
      case 'test'
      when 'tes'
        :ng
      when /te/
        :ng
      else
        :ok
      end
    }
    ae %q{
      case 'test'
      when 'tes'
        :ng
      when /test/
        :ok
      else
        :ng
      end
    }
    ae %q{
      def test(arg)
        case 1
        when 2
          3
        end
        return arg
      end
      
      test(100)
    }
  end

  def test_case_splat
    ae %q{
      ary = [1, 2]
      case 1
      when *ary
        :ok
      else
        :ng
      end
    }
    ae %q{
      ary = [1, 2]
      case 3
      when *ary
        :ng
      else
        :ok
      end
    }
    ae %q{
      ary = [1, 2]
      case 1
      when :x, *ary
        :ok
      when :z
        :ng1
      else
        :ng2
      end
    }
    ae %q{
      ary = [1, 2]
      case 3
      when :x, *ary
        :ng1
      when :z
        :ng2
      else
        :ok
      end
    }
  end

  def test_when
    ae %q(
      case
      when 1==2, 2==3
        :ng1
      when false, 4==5
        :ok
      when false
        :ng2
      else
        :elseng
      end
    )

    ae %q(
      case
      when nil, nil
        :ng1
      when 1,2,3
        :ok
      when false, false
        :ng2
      else
        :elseng
      end
    )
      
    ae %q(
      case
      when nil
        :ng1
      when false
        :ng2
      else
        :elseok
      end)
      
    ae %q{
      case
      when 1
      end
    }

    ae %q{
      r = nil
      ary = []
      case
      when false
        r = :ng1
      when false, false
        r = :ng2
      when *ary
        r = :ng3
      when false, *ary
        r = :ng4
      when true, *ary
        r = :ok
      end
      r
    }
  end

  def test_when_splat
    ae %q{
      ary = []
      case
      when false, *ary
        :ng
      else
        :ok
      end
    }
    ae %q{
      ary = [false, nil]
      case
      when *ary
        :ng
      else
        :ok
      end
    }
    ae %q{
      ary = [false, nil]
      case
      when *ary
        :ng
      when true
        :ok
      else
        :ng2
      end
    }
    ae %q{
      ary = [false, nil]
      case
      when *ary
        :ok
      else
        :ng
      end
    }
    ae %q{
      ary = [false, true]
      case
      when *ary
        :ok
      else
        :ng
      end
    }
    ae %q{
      ary = [false, true]
      case
      when false, false
      when false, *ary
        :ok
      else
        :ng
      end
    }
  end

  def test_flipflop
    ae %q{
      sum = 0
      30.times{|ib|
        if ib % 10 == 0 .. true
          sum += ib
        end
      }
      sum
    }
    ae %q{
      sum = 0
      30.times{|ib|
        if ib % 10 == 0 ... true
          sum += ib
        end
      }
      sum
    }
    ae %q{
      t = nil
      unless ''.respond_to? :lines
        class String
          def lines
            self
          end
        end
      end
      
      "this must not print
      Type: NUM
      123
      456
      Type: ARP
      aaa
      bbb
      \f
      this must not print
      hoge
      Type: ARP
      aaa
      bbb
      ".lines.each{|l|
        if (t = l[/^Type: (.*)/, 1])..(/^\f/ =~ l)
          p [t, l]
        end
      }
    }
  end

  def test_defined_vars
    ae %q{
      defined?(nil) + defined?(self) +
        defined?(true) + defined?(false)
    }
    #ae %q{
    #  a = 1
    #  defined?(a) # yarv returns "in block" in eval context
    #}
    ae %q{
      defined?(@a)
    }
    ae %q{
      @a = 1
      defined?(@a)
    }
    ae %q{
      defined?(@@a)
    }
    ae %q{
      @@a = 1
      defined?(@@a)
    }
    ae %q{
      defined?($a)
    }
    ae %q{
      $a = 1
      defined?($a)
    }
    ae %q{
      defined?(C_definedtest)
    }
    ae %q{
      C_definedtest = 1
      defined?(C_definedtest)
    } do
      remove_const :C_definedtest
    end
    
    ae %q{
      defined?(::C_definedtest)
    }
    ae %q{
      C_definedtest = 1
      defined?(::C_definedtest)
    } do
      remove_const :C_definedtest
    end

    ae %q{
      defined?(C_definedtestA::C_definedtestB::C_definedtestC)
    }
    ae %q{
      class C_definedtestA
        class C_definedtestB
          C_definedtestC = 1
        end
      end
      defined?(C_definedtestA::C_definedtestB::C_definedtestC)
    } do
      remove_const :C_definedtestA
    end
  end

  def test_defined_method
    ae %q{
      defined?(m)
    }
    ae %q{
      def m
      end
      defined?(m)
    }
    
    ae %q{
      defined?(a.class)
    }
    ae %q{
      a = 1
      defined?(a.class)
    }
    ae %q{
      class C
        def test
          [defined?(m1()), defined?(self.m1), defined?(C.new.m1),
           defined?(m2()), defined?(self.m2), defined?(C.new.m2),
           defined?(m3()), defined?(self.m3), defined?(C.new.m3)]
        end
        def m1
        end
        private
        def m2
        end
        protected
        def m3
        end
      end
      C.new.test + [defined?(C.new.m3)]
    }
    ae %q{
      $ans = [defined?($1), defined?($2), defined?($3), defined?($4)]
      /(a)(b)/ =~ 'ab'
      $ans + [defined?($1), defined?($2), defined?($3), defined?($4)]
    }
  end
  
  def test_condition
    ae %q{

      def make_perm ary, num
        if num == 1
          ary.map{|e| [e]}
        else
          base = make_perm(ary, num-1)
          res  = []
          base.each{|b|
            ary.each{|e|
              res << [e] + b
            }
          }
          res
        end
      end
      
      def each_test
        conds = make_perm(['fv', 'tv'], 3)
        bangs = make_perm(['', '!'], 3)
        exprs = make_perm(['and', 'or'], 3)
        ['if', 'unless'].each{|syn|
          conds.each{|cs|
            bangs.each{|bs|
              exprs.each{|es|
                yield(syn, cs, bs, es)
              }
            }
          }
        }
      end
      
      fv = false
      tv = true
      
      $ans = []
      each_test{|syn, conds, bangs, exprs|
        c1, c2, c3 = conds
        bang1, bang2, bang3 = bangs
        e1, e2 = exprs
        eval %Q{
          #{syn} #{bang1}#{c1} #{e1} #{bang2}#{c2} #{e2} #{bang3}#{c3}
            $ans << :then
          else
            $ans << :false
          end
        }
      }
    
      each_test{|syn, conds, bangs, exprs|
        c1, c2, c3 = conds
        bang1, bang2, bang3 = bangs
        e1, e2 = exprs
        eval %Q{
          #{syn} #{bang1}#{c1} #{e1} #{bang2}#{c2} #{e2} #{bang3}#{c3}
            $ans << :then
          end
          $ans << :sep
        }
      }
      $ans
    }
  end
end

