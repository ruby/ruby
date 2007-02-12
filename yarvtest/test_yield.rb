require 'yarvtest/yarvtest'
class TestYield < YarvTestBase
  def test_simple
    ae %q{
      def iter
        yield
      end
      iter{
        1
      }
    }
  end

  def test_hash_each
    ae %q{
      h = {:a => 1}
      a = []
      h.each{|k, v|
        a << [k, v]
      }
      h.each{|kv|
        a << kv
      }
      a
    }
  end

  def test_ary_each
    ae %q{
      ans = []
      ary = [1,2,3]
      ary.each{|a, b, c, d|
        ans << [a, b, c, d]
      }
      ary.each{|a, b, c|
        ans << [a, b, c]
      }
      ary.each{|a, b|
        ans << [a, b]
      }
      ary.each{|a|
        ans << [a]
      }
      ans
    }
  end

  def test_iter
    ae %q{
      def iter *args
        yield *args
      end
      
      ans = []
      ary = [1,2,3]
      ary.each{|a, b, c, d|
        ans << [a, b, c, d]
      }
      ary.each{|a, b, c|
        ans << [a, b, c]
      }
      ary.each{|a, b|
        ans << [a, b]
      }
      ary.each{|a|
        ans << [a]
      }
      ans
    }
  end

  def test_iter2
    ae %q{
      def iter args
        yield *args
      end
      ans = []
      iter([]){|a, b|
        ans << [a, b]
      }
      iter([1]){|a, b|
        ans << [a, b]
      }
      iter([1, 2]){|a, b|
        ans << [a, b]
      }
      iter([1, 2, 3]){|a, b|
        ans << [a, b]
      }
      ans
    }
    ae %q{
      def iter args
        yield *args
      end
      ans = []
      
      iter([]){|a|
        ans << a
      }
      iter([1]){|a|
        ans << a
      }
      iter([1, 2]){|a|
        ans << a
      }
      iter([1, 2, 3]){|a|
        ans << a
      }
      ans
    }
  end

  def test_1_ary_and_n_params
    ae %q{
      def iter args
        yield args
      end
      ans = []
      iter([]){|a, b|
        ans << [a, b]
      }
      iter([1]){|a, b|
        ans << [a, b]
      }
      iter([1, 2]){|a, b|
        ans << [a, b]
      }
      iter([1, 2, 3]){|a, b|
        ans << [a, b]
      }
      ans
    }
  end
  
  def test_1_ary_and_1_params
    ae %q{
      def iter args
        yield args
      end
      ans = []
      iter([]){|a|
        ans << a
      }
      iter([1]){|a|
        ans << a
      }
      iter([1, 2]){|a|
        ans << a
      }
      iter([1, 2, 3]){|a|
        ans << a
      }
      ans
    }
  end
  
  def test_argscat
    ae %q{
      def iter
        yield 1, *[2, 3]
      end

      iter{|a, b, c|
        [a, b, c]
      }
    }
    ae %q{
      def iter
        yield 1, *[]
      end

      iter{|a, b, c|
        [a, b, c]
      }
    }
    if false
      ae %q{
        def iter
          yield 1, *2
        end
        
        iter{|a, b, c|
          [a, b, c]
        }
      }
    end
  end

  def test_massgin
    ae %q{
      ans = []
      [[1, [2, 3]], [4, [5, 6]]].each{|a, (b, c)|
        ans << [a, b, c]
      }
      ans
    }
    ae %q{
      ans = []
      [[1, [2, 3]], [4, [5, 6]]].map{|a, (b, c)|
        ans << [a, b, c]
      } + ans
    }
  end
end


