require 'test/unit'

$KCODE = 'none'

class TestPack < Test::Unit::TestCase
  def test_pack
    $format = "c2x5CCxsdils_l_a6";
    # Need the expression in here to force ary[5] to be numeric.  This avoids
    # test2 failing because ary2 goes str->numeric->str and ary does not.
    ary = [1,-100,127,128,32767,987.654321098 / 100.0,12345,123456,-32767,-123456,"abcdef"]
    $x = ary.pack($format)
    ary2 = $x.unpack($format)
    
    assert(ary.length == ary2.length)
    assert(ary.join(':') == ary2.join(':'))
    assert($x =~ /def/)
    
    $x = [-1073741825]
    assert($x.pack("q").unpack("q") == $x)
  end
end
