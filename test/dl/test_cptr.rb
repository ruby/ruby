require 'test_base'

module DL
  class TestCPtr < TestBase
    def test_free
      ptr = CPtr.malloc(4)
      assert_nil ptr.free
    end

    def test_free=
      free = CFunc.new(@libc['free'], TYPE_VOID, 'free')
      ptr = CPtr.malloc(4)
      ptr.free = free

      assert_equal free.ptr, ptr.free.ptr
    end
  end
end
