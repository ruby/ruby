require 'test/unit'

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

    $x = [-1]
    assert_equal($x, $x.pack("l").unpack("l"))
  end

  def test_pack_n
    assert_equal "\000\000", [0].pack('n')
    assert_equal "\000\001", [1].pack('n')
    assert_equal "\000\002", [2].pack('n')
    assert_equal "\000\003", [3].pack('n')
    assert_equal "\377\376", [65534].pack('n')
    assert_equal "\377\377", [65535].pack('n')

    assert_equal "\200\000", [2**15].pack('n')
    assert_equal "\177\377", [-2**15-1].pack('n')
    assert_equal "\377\377", [-1].pack('n')

    assert_equal "\000\001\000\001", [1,1].pack('n*')
    assert_equal "\000\001\000\001\000\001", [1,1,1].pack('n*')
  end

  def test_unpack_n
    assert_equal 1, "\000\001".unpack('n')[0]
    assert_equal 2, "\000\002".unpack('n')[0]
    assert_equal 3, "\000\003".unpack('n')[0]
    assert_equal 65535, "\377\377".unpack('n')[0]
    assert_equal [1,1], "\000\001\000\001".unpack('n*')
    assert_equal [1,1,1], "\000\001\000\001\000\001".unpack('n*')
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
    assert_equal 4294967295, "\377\377\377\377".unpack('N')[0]
    assert_equal [1,1], "\000\000\000\001\000\000\000\001".unpack('N*')
    assert_equal [1,1,1], "\000\000\000\001\000\000\000\001\000\000\000\001".unpack('N*')
  end

  def test_integer_endian
    s = [1].pack("s")
    assert_operator(["\0\1", "\1\0"], :include?, s)
    if s == "\0\1"
      # big endian
      assert_equal("\x01\x02", [0x0102].pack("s"))
      assert_equal("\x01\x02", [0x0102].pack("S"))
      assert_equal("\x01\x02\x03\x04", [0x01020304].pack("l"))
      assert_equal("\x01\x02\x03\x04", [0x01020304].pack("L"))
      assert_equal("\x01\x02\x03\x04\x05\x06\x07\x08", [0x0102030405060708].pack("q"))
      assert_equal("\x01\x02\x03\x04\x05\x06\x07\x08", [0x0102030405060708].pack("Q"))
      assert_match(/\A\x00*\x01\x02\z/, [0x0102].pack("s!"))
      assert_match(/\A\x00*\x01\x02\z/, [0x0102].pack("S!"))
      assert_match(/\A\x00*\x01\x02\x03\x04\z/, [0x01020304].pack("i"))
      assert_match(/\A\x00*\x01\x02\x03\x04\z/, [0x01020304].pack("I"))
      assert_match(/\A\x00*\x01\x02\x03\x04\z/, [0x01020304].pack("i!"))
      assert_match(/\A\x00*\x01\x02\x03\x04\z/, [0x01020304].pack("I!"))
      assert_match(/\A\x00*\x01\x02\x03\x04\z/, [0x01020304].pack("l!"))
      assert_match(/\A\x00*\x01\x02\x03\x04\z/, [0x01020304].pack("L!"))
      %w[s S l L q Q s! S! i I i! I! l! L!].each {|fmt|
        nuls = [0].pack(fmt)
        v = 0
        s = ""
        nuls.bytesize.times {|i|
          j = i + 40
          v = v * 256 + j
          s << [j].pack("C")
        }
        assert_equal(s, [v].pack(fmt), "[#{v}].pack(#{fmt.dump})")
        assert_equal([v], s.unpack(fmt), "#{s.dump}.unpack(#{fmt.dump})")
        s2 = s+s
        fmt2 = fmt+"*"
        assert_equal([v,v], s2.unpack(fmt2), "#{s2.dump}.unpack(#{fmt2.dump})")
      }
    else
      # little endian
      assert_equal("\x02\x01", [0x0102].pack("s"))
      assert_equal("\x02\x01", [0x0102].pack("S"))
      assert_equal("\x04\x03\x02\x01", [0x01020304].pack("l"))
      assert_equal("\x04\x03\x02\x01", [0x01020304].pack("L"))
      assert_equal("\x08\x07\x06\x05\x04\x03\x02\x01", [0x0102030405060708].pack("q"))
      assert_equal("\x08\x07\x06\x05\x04\x03\x02\x01", [0x0102030405060708].pack("Q"))
      assert_match(/\A\x02\x01\x00*\z/, [0x0102].pack("s!"))
      assert_match(/\A\x02\x01\x00*\z/, [0x0102].pack("S!"))
      assert_match(/\A\x04\x03\x02\x01\x00*\z/, [0x01020304].pack("i"))
      assert_match(/\A\x04\x03\x02\x01\x00*\z/, [0x01020304].pack("I"))
      assert_match(/\A\x04\x03\x02\x01\x00*\z/, [0x01020304].pack("i!"))
      assert_match(/\A\x04\x03\x02\x01\x00*\z/, [0x01020304].pack("I!"))
      assert_match(/\A\x04\x03\x02\x01\x00*\z/, [0x01020304].pack("l!"))
      assert_match(/\A\x04\x03\x02\x01\x00*\z/, [0x01020304].pack("L!"))
      %w[s S l L q Q s! S! i I i! I! l! L!].each {|fmt|
        nuls = [0].pack(fmt)
        v = 0
        s = ""
        nuls.bytesize.times {|i|
          j = i+40
          v = v * 256 + j
          s << [j].pack("C")
        }
        s.reverse!
        assert_equal(s, [v].pack(fmt), "[#{v}].pack(#{fmt.dump})")
        assert_equal([v], s.unpack(fmt), "#{s.dump}.unpack(#{fmt.dump})")
        s2 = s+s
        fmt2 = fmt+"*"
        assert_equal([v,v], s2.unpack(fmt2), "#{s2.dump}.unpack(#{fmt2.dump})")
      }
    end
  end

  def test_pack_U
    assert_raise(RangeError) { [-0x40000001].pack("U") }
    assert_raise(RangeError) { [-0x40000000].pack("U") }
    assert_raise(RangeError) { [-1].pack("U") }
    assert_equal "\000", [0].pack("U")
    assert_equal "\374\277\277\277\277\277", [0x3fffffff].pack("U")
    assert_equal "\375\200\200\200\200\200", [0x40000000].pack("U")
    assert_equal "\375\277\277\277\277\277", [0x7fffffff].pack("U")
    assert_raise(RangeError) { [0x80000000].pack("U") }
    assert_raise(RangeError) { [0x100000000].pack("U") }
  end

  def test_pack_P
    a = ["abc"]
    assert_equal a, a.pack("P").unpack("P*")
    assert_equal "a", a.pack("P").unpack("P")[0]
    assert_equal a, a.pack("P").freeze.unpack("P*")
    assert_raise(ArgumentError) { (a.pack("P") + "").unpack("P*") }
  end

  def test_pack_p
    a = ["abc"]
    assert_equal a, a.pack("p").unpack("p*")
    assert_equal a[0], a.pack("p").unpack("p")[0]
    assert_equal a, a.pack("p").freeze.unpack("p*")
    assert_raise(ArgumentError) { (a.pack("p") + "").unpack("p*") }
  end

  def test_format_string_modified
    fmt = "CC"
    o = Object.new
    class << o; self; end.class_eval do
      define_method(:to_int) { fmt.replace ""; 0 }
    end
    assert_raise(RuntimeError) do
      [o, o].pack(fmt)
    end
  end

  def test_comment
    assert_equal("\0\1", [0,1].pack("  C  #foo \n  C  "))
    assert_equal([0,1], "\0\1".unpack("  C  #foo \n  C  "))
  end

  def test_illegal_bang
    assert_raise(ArgumentError) { [].pack("a!") }
    assert_raise(ArgumentError) { "".unpack("a!") }
  end

  def test_pack_unpack_aA
    assert_equal("f", ["foo"].pack("A"))
    assert_equal("f", ["foo"].pack("a"))
    assert_equal("foo", ["foo"].pack("A*"))
    assert_equal("foo", ["foo"].pack("a*"))
    assert_equal("fo", ["foo"].pack("A2"))
    assert_equal("fo", ["foo"].pack("a2"))
    assert_equal("foo ", ["foo"].pack("A4"))
    assert_equal("foo\0", ["foo"].pack("a4"))
    assert_equal(" ", [nil].pack("A"))
    assert_equal("\0", [nil].pack("a"))
    assert_equal("", [nil].pack("A*"))
    assert_equal("", [nil].pack("a*"))
    assert_equal("  ", [nil].pack("A2"))
    assert_equal("\0\0", [nil].pack("a2"))

    assert_equal("foo" + "\0" * 27, ["foo"].pack("a30"))

    assert_equal(["f"], "foo\0".unpack("A"))
    assert_equal(["f"], "foo\0".unpack("a"))
    assert_equal(["foo"], "foo\0".unpack("A4"))
    assert_equal(["foo\0"], "foo\0".unpack("a4"))
    assert_equal(["foo"], "foo ".unpack("A4"))
    assert_equal(["foo "], "foo ".unpack("a4"))
    assert_equal(["foo"], "foo".unpack("A4"))
    assert_equal(["foo"], "foo".unpack("a4"))
  end

  def test_pack_unpack_Z
    assert_equal("f", ["foo"].pack("Z"))
    assert_equal("foo\0", ["foo"].pack("Z*"))
    assert_equal("fo", ["foo"].pack("Z2"))
    assert_equal("foo\0\0", ["foo"].pack("Z5"))
    assert_equal("\0", [nil].pack("Z"))
    assert_equal("\0", [nil].pack("Z*"))
    assert_equal("\0\0", [nil].pack("Z2"))

    assert_equal(["f"], "foo\0".unpack("Z"))
    assert_equal(["foo"], "foo".unpack("Z*"))
    assert_equal(["foo"], "foo\0".unpack("Z*"))
    assert_equal(["foo"], "foo".unpack("Z5"))
  end

  def test_pack_unpack_bB
    assert_equal("\xff\x00", ["1111111100000000"].pack("b*"))
    assert_equal("\x01\x02", ["1000000001000000"].pack("b*"))
    assert_equal("", ["1"].pack("b0"))
    assert_equal("\x01", ["1"].pack("b1"))
    assert_equal("\x01\x00", ["1"].pack("b2"))
    assert_equal("\x01\x00", ["1"].pack("b3"))
    assert_equal("\x01\x00\x00", ["1"].pack("b4"))
    assert_equal("\x01\x00\x00", ["1"].pack("b5"))
    assert_equal("\x01\x00\x00\x00", ["1"].pack("b6"))

    assert_equal("\xff\x00", ["1111111100000000"].pack("B*"))
    assert_equal("\x01\x02", ["0000000100000010"].pack("B*"))
    assert_equal("", ["1"].pack("B0"))
    assert_equal("\x80", ["1"].pack("B1"))
    assert_equal("\x80\x00", ["1"].pack("B2"))
    assert_equal("\x80\x00", ["1"].pack("B3"))
    assert_equal("\x80\x00\x00", ["1"].pack("B4"))
    assert_equal("\x80\x00\x00", ["1"].pack("B5"))
    assert_equal("\x80\x00\x00\x00", ["1"].pack("B6"))

    assert_equal(["1111111100000000"], "\xff\x00".unpack("b*"))
    assert_equal(["1000000001000000"], "\x01\x02".unpack("b*"))
    assert_equal([""], "".unpack("b0"))
    assert_equal(["1"], "\x01".unpack("b1"))
    assert_equal(["10"], "\x01".unpack("b2"))
    assert_equal(["100"], "\x01".unpack("b3"))

    assert_equal(["1111111100000000"], "\xff\x00".unpack("B*"))
    assert_equal(["0000000100000010"], "\x01\x02".unpack("B*"))
    assert_equal([""], "".unpack("B0"))
    assert_equal(["1"], "\x80".unpack("B1"))
    assert_equal(["10"], "\x80".unpack("B2"))
    assert_equal(["100"], "\x80".unpack("B3"))
  end

  def test_pack_unpack_hH
    assert_equal("\x01\xfe", ["10ef"].pack("h*"))
    assert_equal("", ["10ef"].pack("h0"))
    assert_equal("\x01\x0e", ["10ef"].pack("h3"))
    assert_equal("\x01\xfe\x0", ["10ef"].pack("h5"))
    assert_equal("\xff\x0f", ["fff"].pack("h3"))
    assert_equal("\xff\x0f", ["fff"].pack("h4"))
    assert_equal("\xff\x0f\0", ["fff"].pack("h5"))
    assert_equal("\xff\x0f\0", ["fff"].pack("h6"))
    assert_equal("\xff\x0f\0\0", ["fff"].pack("h7"))
    assert_equal("\xff\x0f\0\0", ["fff"].pack("h8"))

    assert_equal("\x10\xef", ["10ef"].pack("H*"))
    assert_equal("", ["10ef"].pack("H0"))
    assert_equal("\x10\xe0", ["10ef"].pack("H3"))
    assert_equal("\x10\xef\x0", ["10ef"].pack("H5"))
    assert_equal("\xff\xf0", ["fff"].pack("H3"))
    assert_equal("\xff\xf0", ["fff"].pack("H4"))
    assert_equal("\xff\xf0\0", ["fff"].pack("H5"))
    assert_equal("\xff\xf0\0", ["fff"].pack("H6"))
    assert_equal("\xff\xf0\0\0", ["fff"].pack("H7"))
    assert_equal("\xff\xf0\0\0", ["fff"].pack("H8"))

    assert_equal(["10ef"], "\x01\xfe".unpack("h*"))
    assert_equal([""], "\x01\xfe".unpack("h0"))
    assert_equal(["1"], "\x01\xfe".unpack("h1"))
    assert_equal(["10"], "\x01\xfe".unpack("h2"))
    assert_equal(["10e"], "\x01\xfe".unpack("h3"))
    assert_equal(["10ef"], "\x01\xfe".unpack("h4"))
    assert_equal(["10ef"], "\x01\xfe".unpack("h5"))

    assert_equal(["10ef"], "\x10\xef".unpack("H*"))
    assert_equal([""], "\x10\xef".unpack("H0"))
    assert_equal(["1"], "\x10\xef".unpack("H1"))
    assert_equal(["10"], "\x10\xef".unpack("H2"))
    assert_equal(["10e"], "\x10\xef".unpack("H3"))
    assert_equal(["10ef"], "\x10\xef".unpack("H4"))
    assert_equal(["10ef"], "\x10\xef".unpack("H5"))
  end
end
