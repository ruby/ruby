require 'test/unit'

class TestBignum < Test::Unit::TestCase
  def fact(n)
    return 1 if n == 0
    f = 1
    while n>0
      f *= n
      n -= 1
    end
    return f
  end

  def test_bignum
    $x = fact(40)
    assert_equal($x, $x)
    assert_equal($x, fact(40))
    assert($x < $x+2)
    assert($x > $x-2)
    assert_equal(815915283247897734345611269596115894272000000000, $x)
    assert_not_equal(815915283247897734345611269596115894272000000001, $x)
    assert_equal(815915283247897734345611269596115894272000000001, $x+1)
    assert_equal(335367096786357081410764800000, $x/fact(20))
    $x = -$x
    assert_equal(-815915283247897734345611269596115894272000000000, $x)
    assert_equal(2-(2**32), -(2**32-2))
    assert_equal(2**32 - 5, (2**32-3)-2)

    for i in 1000..1014
      assert_equal(2 ** i, 1 << i)
    end

    n1 = 1 << 1000
    for i in 1000..1014
      assert_equal(n1, 1 << i)
      n1 *= 2
    end

    n2=n1
    for i in 1..10
      n1 = n1 / 2
      n2 = n2 >> 1
      assert_equal(n1, n2)
    end

    for i in 4000..4096
      n1 = 1 << i;
      assert_equal(n1-1, (n1**2-1) / (n1+1))
    end
  end

  def test_calc
    b = 10**80
    a = b * 9 + 7
    assert_equal(7, a.modulo(b))
    assert_equal(-b + 7, a.modulo(-b))
    assert_equal(b + -7, (-a).modulo(b))
    assert_equal(-7, (-a).modulo(-b))
    assert_equal(7, a.remainder(b))
    assert_equal(7, a.remainder(-b))
    assert_equal(-7, (-a).remainder(b))
    assert_equal(-7, (-a).remainder(-b))

    assert_equal(10000000000000000000100000000000000000000, 10**40+10**20)
    assert_equal(100000000000000000000, 10**40/10**20)

    a = 677330545177305025495135714080
    b = 14269972710765292560
    assert_equal(0, a % b)
    assert_equal(0, -a % b)
  end

  def shift_test(a)
    b = a / (2 ** 32)
    c = a >> 32
    assert_equal(b, c)

    b = a * (2 ** 32)
    c = a << 32
    assert_equal(b, c)
  end

  def test_shift
    shift_test(-4518325415524767873)
    shift_test(-0xfffffffffffffffff)
  end

  def test_to_s  # [ruby-core:10686]
    assert_equal("fvvvvvvvvvvvv" ,18446744073709551615.to_s(32))
    assert_equal("g000000000000" ,18446744073709551616.to_s(32))
    assert_equal("3w5e11264sgsf" ,18446744073709551615.to_s(36))
    assert_equal("3w5e11264sgsg" ,18446744073709551616.to_s(36))
    assert_equal("nd075ib45k86f" ,18446744073709551615.to_s(31))
    assert_equal("nd075ib45k86g" ,18446744073709551616.to_s(31))
    assert_equal("1777777777777777777777" ,18446744073709551615.to_s(8))
    assert_equal("-1777777777777777777777" ,-18446744073709551615.to_s(8))
  end

  def test_too_big_to_s
    if (big = 2**31-1).is_a?(Fixnum)
      return
    end
    e = assert_raise(RangeError) {(1 << big).to_s}
    assert_match(/too big to convert/, e.message)
  end

  def test_to_f
    inf = 1 / 0.0
    assert_equal(inf,  (1  << 65536).to_f)
    assert_equal(-inf, (-1 << 65536).to_f) # [ruby-core:30492] [Bug #3362]
  end
end
