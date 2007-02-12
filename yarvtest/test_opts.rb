require 'yarvtest/yarvtest'

class TestOpt < YarvTestBase
  def test_plus
    ae %q{
      a, b = 1, 2
      a+b
    }
    ae %q{
      class Fixnum
        def +(*o)
          o
        end
        def -(*o)
          o
        end
      end
      [10+11, 100-101]
    }
    ae %q{
      class Float
        def +(o)
          self * o
        end
      end
      
      a, b = 1, 2
      a+b
    }
  end

  def test_opt_methdos
    klasses = [[Fixnum, 2, 3], [Float, 1.1, 2.2],
    [String, "abc", "def"], [Array, [1,2,3], [4, 5]],
    [Hash, {:a=>1, :b=>2}, {:x=>"foo", :y=>"bar"}]]
    
    bin_methods = [:+, :-, :*, :/, :%, ]
    one_methods = [:length, :succ, ]
    ary = []
    
    bin_methods.each{|m|
      klasses.each{|klass, obj, arg|
        str = %{
          ary = []
          if (#{obj.inspect}).respond_to? #{m.inspect}
            begin
              ary << (#{obj.inspect}).#{m.to_s}(#{arg.inspect})
            rescue Exception => e
              ary << :error
            end
          end
          
          class #{klass}
            def #{m}(o)
              [#{m.inspect}, :bin, #{klass}].inspect
            end
          end
          ary << (#{obj.inspect}).#{m.to_s}(#{arg.inspect})
          ary
        }
        ae str
      }
    }
    one_methods.each{|m|
      klasses.each{|klass, obj|
        str = %{
          ary = []
          if (#{obj.inspect}).respond_to? #{m.inspect}
            ary << (#{obj.inspect}).#{m.to_s}()
          end
          
          class #{klass}
            def #{m}()
              [#{m.inspect}, self, #{klass}].inspect
            end
          end
          ary << (#{obj.inspect}).#{m.to_s}()
          ary
        }
        ae str
      }
    }
  end

  def test_opt_plus
    ae %q{
      temp = 2**30 - 5
      (1..5).map do
        temp += 1
        [temp, temp.class]
      end
    }
    ae %q{
      temp = -(2**30 - 5)
      (1..10).map do
        temp += 1
        [temp, temp.class]
      end
    }
  end

  def test_eq
    ae %q{
      class Foo
        def ==(other)
          true
        end
      end
      foo = Foo.new
      [1.0 == foo,
       1 == foo,
       "abc" == foo,
       ]
    }
  end
end


