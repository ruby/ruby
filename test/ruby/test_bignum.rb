require 'test/unit'

$KCODE = 'none'

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
    assert($x == $x)
    assert($x == fact(40))
    assert($x < $x+2)
    assert($x > $x-2)
    assert($x == 815915283247897734345611269596115894272000000000)
    assert($x != 815915283247897734345611269596115894272000000001)
    assert($x+1 == 815915283247897734345611269596115894272000000001)
    assert($x/fact(20) == 335367096786357081410764800000)
    $x = -$x
    assert($x == -815915283247897734345611269596115894272000000000)
    assert(2-(2**32) == -(2**32-2))
    assert(2**32 - 5 == (2**32-3)-2)

    $good = true;
    for i in 1000..1014
      $good = false if ((1<<i) != (2**i))
    end
    assert($good)
    
    $good = true;
    n1=1<<1000
    for i in 1000..1014
      $good = false if ((1<<i) != n1)
      n1 *= 2
    end
    assert($good)
    
    $good = true;
    n2=n1
    for i in 1..10
      n1 = n1 / 2
      n2 = n2 >> 1
      $good = false if (n1 != n2)
    end
    assert($good)
    
    $good = true;
    for i in 4000..4096
      n1 = 1 << i;
      if (n1**2-1) / (n1+1) != (n1-1)
        p i
        $good = false
      end
    end
    assert($good)
  end

  def test_calc
    b = 10**80
    a = b * 9 + 7
    assert(7 == a.modulo(b))
    assert(-b + 7 == a.modulo(-b))
    assert(b + -7 == (-a).modulo(b))
    assert(-7 == (-a).modulo(-b))
    assert(7 == a.remainder(b))
    assert(7 == a.remainder(-b))
    assert(-7 == (-a).remainder(b))
    assert(-7 == (-a).remainder(-b))
    
    assert(10**40+10**20 == 10000000000000000000100000000000000000000)
    assert(10**40/10**20 == 100000000000000000000)
    
    a = 677330545177305025495135714080
    b = 14269972710765292560
    assert(a % b == 0)
    assert(-a % b == 0)
  end

  def test_shift
    def shift_test(a)
      b = a / (2 ** 32)
      c = a >> 32
      assert(b == c)
    
      b = a * (2 ** 32)
      c = a << 32
      assert(b == c)
    end
    
    shift_test(-4518325415524767873)
    shift_test(-0xfffffffffffffffff)
  end
end
