require 'test/unit'

class TestFixnum < Test::Unit::TestCase
  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  def teardown
    $VERBOSE = @verbose
  end

  def test_pow
    [1, 2, 2**64, 2**63*3, 2**64*3].each do |y|
      [-1, 0, 1].each do |x|
        z1 = x**y
        z2 = (-x)**y
        if y % 2 == 1
          assert_equal(z2, -z1)
        else
          assert_equal(z2, z1)
        end
      end
    end
  end

  def test_succ
    assert_equal(0x40000000, 0x3fffffff.succ, "[ruby-dev:31189]")
    assert_equal(0x4000000000000000, 0x3fffffffffffffff.succ, "[ruby-dev:31190]")
  end

  def test_pred
    assert_equal(-0x40000001, (-0x40000000).pred)
    assert_equal(-0x4000000000000001, (-0x4000000000000000).pred)
  end

  def test_plus
    assert_equal(0x40000000, 0x3fffffff+1)
    assert_equal(0x4000000000000000, 0x3fffffffffffffff+1)
    assert_equal(-0x40000001, (-0x40000000)+(-1))
    assert_equal(-0x4000000000000001, (-0x4000000000000000)+(-1))
    assert_equal(-0x80000000, (-0x40000000)+(-0x40000000))
  end

  def test_sub
    assert_equal(0x40000000, 0x3fffffff-(-1))
    assert_equal(0x4000000000000000, 0x3fffffffffffffff-(-1))
    assert_equal(-0x40000001, (-0x40000000)-1)
    assert_equal(-0x4000000000000001, (-0x4000000000000000)-1)
    assert_equal(-0x80000000, (-0x40000000)-0x40000000)
  end

  def test_mult
    assert_equal(0x40000000, 0x20000000*2)
    assert_equal(0x4000000000000000, 0x2000000000000000*2)
    assert_equal(-0x40000001, 33025*(-32513))
    assert_equal(-0x4000000000000001, 1380655685*(-3340214413))
    assert_equal(0x40000000, (-0x40000000)*(-1))
  end

  def test_div
    assert_equal(2, 5/2)
    assert_equal(0, 1/2)
    assert_equal(-1, -1/2)
    assert_equal(0, -(1/2))
    assert_equal(-1, (-1)/2)
    assert_equal(0, (-1)/(-2))
    assert_equal(-1, 1/(-2))
    assert_equal(1, -(1/(-2)))
    assert_equal(0x3fffffff, 0xbffffffd/3)
    assert_equal(0x40000000, 0xc0000000/3)
    assert_equal(0x4000000000000000, 0xc000000000000000/3)
    assert_equal(-0x40000001, 0xc0000003/(-3))
    assert_equal(-0x4000000000000001, 0xc000000000000003/(-3))
    assert_equal(0x40000000, (-0x40000000)/(-1), "[ruby-dev:31210]")
    assert_equal(0x4000000000000000, (-0x4000000000000000)/(-1))
  end

  def test_mod
    assert_equal(2, (-0x40000000) % 3)
    assert_equal(0, (-0x40000000) % (-1))
  end

  def test_divmod
    (-5).upto(5) {|a|
      (-5).upto(5) {|b|
        next if b == 0
        q, r = a.divmod(b)
        assert_equal(a, b*q+r)
        assert(r.abs < b.abs)
        assert(0 < b ? (0 <= r && r < b) : (b < r && r <= 0))
        assert_equal(q, a/b)
        assert_equal(q, a.div(b))
        assert_equal(r, a%b)
        assert_equal(r, a.modulo(b))
      }
    }
  end

  def test_not
    assert_equal(-0x40000000, ~0x3fffffff)
    assert_equal(0x3fffffff, ~-0x40000000)
  end

  def test_lshift
    assert_equal(0x40000000, 0x20000000<<1)
    assert_equal(-0x40000000, (-0x20000000)<<1)
    assert_equal(-0x80000000, (-0x40000000)<<1)
  end

  def test_rshift
    assert_equal(0x20000000, 0x40000000>>1)
    assert_equal(-0x20000000, (-0x40000000)>>1)
    assert_equal(-0x40000000, (-0x80000000)>>1)
  end

  def test_abs
    assert_equal(0x40000000, (-0x40000000).abs)
    assert_equal(0x4000000000000000, (-0x4000000000000000).abs)
  end
end
