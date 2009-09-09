require 'test_base.rb'
require 'dl/callback'

module DL
class TestDL < TestBase
  def test_call_int()
    cfunc = CFunc.new(@libc['atoi'], TYPE_INT, 'atoi')
    x = cfunc.call(["100"].pack("p").unpack("l!*"))
    assert_equal(100, x)

    cfunc = CFunc.new(@libc['atoi'], TYPE_INT, 'atoi')
    x = cfunc.call(["-100"].pack("p").unpack("l!*"))
    assert_equal(-100, x)
  end

  def test_call_long()
    cfunc = CFunc.new(@libc['atol'], TYPE_LONG, 'atol')
    x = cfunc.call(["100"].pack("p").unpack("l!*"))
    assert_equal(100, x)
    cfunc = CFunc.new(@libc['atol'], TYPE_LONG, 'atol')
    x = cfunc.call(["-100"].pack("p").unpack("l!*"))
    assert_equal(-100, x)
  end

  def test_call_double()
    cfunc = CFunc.new(@libc['atof'], TYPE_DOUBLE, 'atof')
    x = cfunc.call(["0.1"].pack("p").unpack("l!*"))
    assert_in_delta(0.1, x)

    cfunc = CFunc.new(@libc['atof'], TYPE_DOUBLE, 'atof')
    x = cfunc.call(["-0.1"].pack("p").unpack("l!*"))
    assert_in_delta(-0.1, x)
  end

  def test_sin()
    pi_2 = Math::PI/2
    cfunc = CFunc.new(@libm['sin'], TYPE_DOUBLE, 'sin')
    x = cfunc.call([pi_2].pack("d").unpack("l!*"))
    assert_equal(Math.sin(pi_2), x)

    cfunc = CFunc.new(@libm['sin'], TYPE_DOUBLE, 'sin')
    x = cfunc.call([-pi_2].pack("d").unpack("l!*"))
    assert_equal(Math.sin(-pi_2), x)
  end

  def test_strlen()
    cfunc = CFunc.new(@libc['strlen'], TYPE_INT, 'strlen')
    x = cfunc.call(["abc"].pack("p").unpack("l!*"))
    assert_equal("abc".size, x)
  end

  def test_strcpy()
    buff = "xxxx"
    str  = "abc"
    cfunc = CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy')
    x = cfunc.call([buff,str].pack("pp").unpack("l!*"))
    assert_equal("abc\0", buff)
    assert_equal("abc\0", CPtr.new(x).to_s(4))

    buff = "xxxx"
    str  = "abc"
    cfunc = CFunc.new(@libc['strncpy'], TYPE_VOIDP, 'strncpy')
    x = cfunc.call([buff,str,3].pack("ppL!").unpack("l!*"))
    assert_equal("abcx", buff)
    assert_equal("abcx", CPtr.new(x).to_s(4))

    ptr = CPtr.malloc(4)
    str = "abc"
    cfunc = CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy')
    x = cfunc.call([ptr.to_i,str].pack("l!p").unpack("l!*"))
    assert_equal("abc\0", ptr[0,4])
    assert_equal("abc\0", CPtr.new(x).to_s(4))
  end

  def test_callback()
    buff = "foobarbaz"
    cb = set_callback(TYPE_INT,2){|x,y| CPtr.new(x)[0] <=> CPtr.new(y)[0]}
    cfunc = CFunc.new(@libc['qsort'], TYPE_VOID, 'qsort')
    cfunc.call([buff, buff.size, 1, cb].pack("pL!L!L!").unpack("l!*"))
    assert_equal('aabbfoorz', buff)
  end

  def test_dlwrap()
    ary = [0,1,2,4,5]
    addr = dlwrap(ary)
    ary2 = dlunwrap(addr)
    assert_equal(ary, ary2)
  end

  def test_cptr()
    check = Proc.new{|str,ptr|
      assert_equal(str.size(), ptr.size())
      assert_equal(str, ptr.to_s())
      assert_equal(str[0,2], ptr.to_s(2))
      assert_equal(str[0,2], ptr[0,2])
      assert_equal(str[1,2], ptr[1,2])
      assert_equal(str[1,0], ptr[1,0])
      assert_equal(str[0].ord, ptr[0])
      assert_equal(str[1].ord, ptr[1])
    }
    str = 'abc'
    ptr = CPtr[str]
    check.call(str, ptr)
    str[0] = "c"
    ptr[0] = "c".ord
    check.call(str, ptr)
    str[0,2] = "aa"
    ptr[0,2] = "aa"
    check.call(str, ptr)
  end
end
end # module DL
