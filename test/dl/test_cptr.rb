require 'test_base'
require_relative '../ruby/envutil'

module DL
  class TestCPtr < TestBase
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
  end
end
