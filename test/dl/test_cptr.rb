require_relative 'test_base'
require_relative '../ruby/envutil'

module DL
  class TestCPtr < TestBase
    def test_ref_ptr
      ary = [0,1,2,4,5]
      addr = CPtr.new(dlwrap(ary))
      assert_equal addr.to_i, addr.ref.ptr.to_i

      assert_equal addr.to_i, (+ (- addr)).to_i
    end

    def test_to_value
      ary = [0,1,2,4,5]
      addr = CPtr.new(dlwrap(ary))
      assert_equal ary, addr.to_value
    end

    def test_free
      ptr = CPtr.malloc(4)
      assert_nil ptr.free
    end

    def test_free=
      assert_normal_exit(<<-"End", '[ruby-dev:39269]')
        require 'dl'
        DL::LIBC_SO = #{DL::LIBC_SO.dump}
        DL::LIBM_SO = #{DL::LIBM_SO.dump}
        include DL
        @libc = dlopen(LIBC_SO)
        @libm = dlopen(LIBM_SO)
        free = CFunc.new(@libc['free'], TYPE_VOID, 'free')
        ptr = CPtr.malloc(4)
        ptr.free = free
        free.ptr
        ptr.free.ptr
      End

      free = CFunc.new(@libc['free'], TYPE_VOID, 'free')
      ptr = CPtr.malloc(4)
      ptr.free = free

      assert_equal free.ptr, ptr.free.ptr
    end

    def test_null?
      ptr = CPtr.new(0)
      assert ptr.null?
    end

    def test_size
      ptr = CPtr.malloc(4)
      assert_equal 4, ptr.size
      DL.free ptr.to_i
    end

    def test_size=
      ptr = CPtr.malloc(4)
      ptr.size = 10
      assert_equal 10, ptr.size
      DL.free ptr.to_i
    end

    def test_aref_aset
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
      assert_equal 'c'.ord, ptr[0] = "c".ord
      check.call(str, ptr)

      str[0,2] = "aa"
      assert_equal 'aa', ptr[0,2] = "aa"
      check.call(str, ptr)

      ptr2 = CPtr['cdeeee']
      str[0,2] = "cd"
      assert_equal ptr2, ptr[0,2] = ptr2
      check.call(str, ptr)

      ptr3 = CPtr['vvvv']
      str[0,2] = "vv"
      assert_equal ptr3.to_i, ptr[0,2] = ptr3.to_i
      check.call(str, ptr)
    end
  end
end
