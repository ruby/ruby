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

    assert_equal(ary.length, ary2.length)
    assert_equal(ary.join(':'), ary2.join(':'))
    assert_match(/def/, $x)

    $x = [-1073741825]
    assert_equal($x, $x.pack("q").unpack("q"))
  end

  def test_pack_N
    assert_equal "\000\000\000\000", [0].pack('N')
    assert_equal "\000\000\000\001", [1].pack('N')
    assert_equal "\000\000\000\002", [2].pack('N')
    assert_equal "\000\000\000\003", [3].pack('N')
    assert_equal "\377\377\377\376", [4294967294].pack('N')
    assert_equal "\377\377\377\377", [4294967295].pack('N')

    assert_equal "\200\000\000\000", [2**31].pack('N')
    assert_equal "\177\377\377\377", [-2**31-1].pack('N')
    assert_equal "\377\377\377\377", [-1].pack('N')

    assert_equal "\000\000\000\001\000\000\000\001", [1,1].pack('N*')
    assert_equal "\000\000\000\001\000\000\000\001\000\000\000\001", [1,1,1].pack('N*')
  end

  def test_unpack_N
    assert_equal 1, "\000\000\000\001".unpack('N')[0]
    assert_equal 2, "\000\000\000\002".unpack('N')[0]
    assert_equal 3, "\000\000\000\003".unpack('N')[0]
    assert_equal 3, "\000\000\000\003".unpack('N')[0]
    assert_equal 4294967295, "\377\377\377\377".unpack('N')[0]
    assert_equal [1,1], "\000\000\000\001\000\000\000\001".unpack('N*')
    assert_equal [1,1,1], "\000\000\000\001\000\000\000\001\000\000\000\001".unpack('N*')
  end
end
