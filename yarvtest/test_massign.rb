require 'yarvtest/yarvtest'

# test of syntax
class TestMassign < YarvTestBase
  def test_simle
    ae %q{
      a = :a; b = :b; c = :c
      x, y = a, b
      [x, y]
    }
    ae %q{
      a = :a; b = :b; c = :c
      x, y, z = a, b, c
      [x, y, z]
    }
  end

  def test_diff_elems
    ae %q{
      a = :a ; b = :b ; c = :c
      x, y, z = a, b
      [x, y, z]
    }
    ae %q{
      a = :a; b = :b; c = :c
      x, y = a, b, c
      [x, y]
    }
  end

  def test_single_l
    ae %q{
      a = :a; b = :b
      x = a, b
      x
    }
    ae %q{
      a = [1, 2]; b = [3, 4]
      x = a, b
      x
    }
  end

  def test_single_r
    ae %q{
      a = :a
      x, y = a
      [x, y]
    }
    ae %q{
      a = [1, 2]
      x, y = a
      [x, y]
    }
    ae %q{
      a = [1, 2, 3]
      x, y = a
      [x, y]
    }
  end
  
  def test_splat_l
    ae %q{
      a = :a; b = :b; c = :c
      *x = a, b
      [x]
    }
    ae %q{
      a = :a; b = :b; c = :c
      *x = a, b
      [x]
    }
    ae %q{
      a = :a; b = :b; c = :c
      x, * = a, b
      [x]
    }
    ae %q{
      a = :a; b = :b; c = :c
      x, *y = a, b
      [x, y]
    }
    ae %q{
      a = :a; b = :b; c = :c
      x, y, *z = a, b
      [x, y]
    }
    ae %q{ # only one item on rhs
      *x = :x
      x
    }
    ae %q{ # nil on rhs
      *x = nil
      x
    }
  end

  def test_splat_r
    if false
      ae %q{
        a = :a; b = :b; c = :c
        x, y = *a
        [x, y]
      }
      ae %q{
        a = :a; b = :b; c = :c
        x, y = a, *b
        [x, y]
      }
      ae %q{
        a = :a; b = :b; c = :c
        x, y = a, b, *c
        [x, y]
      }
      ae %q{
        x=*nil
        x
      }
    end
    
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      x, y = *a
      [x, y]
    }
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      x, y = a, *b
      [x, y]
    }
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      x, y = a, b, *c
      [x, y]
    }
  end

  def test_splat_b1
    if false
      # error
      ae %q{
        a = :a; b = :b; c = :c
        x, *y = *a
        [x, y]
      }
      ae %q{
        a = :a; b = :b; c = :c
        x, *y = a, *b
        [x, y]
      }
      ae %q{
        a = :a; b = :b; c = :c
        x, *y = a, b, *c
        [x, y]
      }
    end

    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      x, *y = *a
      [x, y]
    }
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      x, *y = a, *b
      [x, y]
    }
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      x, *y = a, b, *c
      [x, y]
    }
  end

  def test_splat_b2
    if false
      # error
      ae %q{
        a = :a; b = :b; c = :c
        *x = *a
        x
      }
      ae %q{
        a = :a; b = :b; c = :c
        *x = a, *b
        x
      }
      ae %q{
        a = :a; b = :b; c = :c
        *x = a, b, *c
        x
      }
    end

    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      *x = *a
      x
    }
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      *x = a, *b
      x
    }
    ae %q{
      a = [:a, :a2]; b = [:b, :b2]; c = [:c, :c2]
      *x = a, b, *c
      x
    }
  end

  def test_toary
    ae %q{
      x, y = :a
      [x, y]
    }
    ae %q{
      x, y = [1, 2]
      [x, y]
    }
    ae %q{
      x, y = [1, 2, 3]
      [x, y]
    }
  end

  def test_swap
    ae %q{
      a = 1; b = 2
      a, b = b, a
      [a, b]
    }
  end
  
  def test_mret
    ae %q{
      def m
        return 1, 2
      end

      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return 1, 2
      end

      a = m
      [a]
    }
    ae %q{
      def m
        return 1
      end

      a, b = m
      [a, b]
    }
  end

  def test_mret_splat
    if false
      ae %q{
        def m
          return *1
        end
        a, b = m
        [a, b]
      }
    end
    
    ae %q{
      def m
        return *[]
      end
      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return *[1]
      end
      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return *[1,2]
      end
      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return *[1,2,3]
      end
      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return *[1]
      end
      a = m
    }
  end

  def test_mret_argscat
    ae %q{
      def m
        return 1, *[]
      end
      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return 1, 2, *[1]
      end
      a, b = m
      [a, b]
    }
    ae %q{
      def m
        return 1, 2, 3, *[1,2]
      end
      a, b = m
      [a, b]
    }
  end

  def test_nested_massign
    ae %q{
      (a, b), c = [[1, 2], 3]
      [a, b, c]
    }
    ae %q{
      a, (b, c) = [[1, 2], 3]
      [a, b, c]
    }
    ae %q{
      a, (b, c) = [1, [2, 3]]
      [a, b, c]
    }
    ae %q{
      (a, b), *c = [[1, 2], 3]
      [a, b, c]
    }
    ae %q{
      (a, b), c, (d, e) = [[1, 2], 3, [4, 5]]
      [a, b, c, d, e]
    }
    ae %q{
      (a, *b), c, (d, e, *) = [[1, 2], 3, [4, 5]]
      [a, b, c, d, e]
    }
    ae %q{
      (a, b), c, (d, *e) = [[1, 2, 3], 3, [4, 5, 6, 7]]
      [a, b, c, d, e]
    }
    ae %q{
      (a, (b1, b2)), c, (d, e) = [[1, 2], 3, [4, 5]]
      [a, b1, b2, c, d, e]
    }
    ae %q{
      (a, (b1, b2)), c, (d, e) = [[1, [21, 22]], 3, [4, 5]]
      [a, b1, b2, c, d, e]
    }
  end

  # ignore
  def _test_massign_value
    # Value of this massign statement should be [1, 2, 3]
    ae %q{
      a, b, c = [1, 2, 3]
    }
  end
  
  def test_nested_splat
    # Somewhat obscure nested splat
    ae %q{
      a = *[*[1]]
      a
    }
  end
  
  def test_calls_to_a
    # Should be result of calling to_a on arg, ie [[1, 2], [3, 4]]
    ae %q{
      x=*{1=>2,3=>4}
      x
    }
  end
  
  def test_const_massign
    ae %q{
      class C
        class D
        end
      end
      
      X, Y = 1, 2
      Z, C::Const, C::D::Const, ::C::Const2 = 3, 4, 5, 6
      [X, Y, Z, C::Const, C::D::Const, ::C::Const2]
    }
  end

  def test_massign_values
    ae %q{
      ary = [1, 2].partition {|n| n == 1 }
      a, b = ary
      [a, b]
    }
  end
end

