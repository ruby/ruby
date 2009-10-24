require 'test_base'

module DL
  class TestHandle < TestBase
    def test_handle_close
      handle = DL::Handle.new(LIBC_SO)
      assert_equal 0, handle.close
    end

    def test_handle_close_twice
      handle = DL::Handle.new(LIBC_SO)
      handle.close
      assert_raises(DL::DLError) do
        handle.close
      end
    end

    def test_dlopen_returns_handle
      assert_instance_of DL::Handle, dlopen(LIBC_SO)
    end

    def test_dlopen_safe
      assert_raises(SecurityError) do
        Thread.new do
          $SAFE = 2
          dlopen(LIBC_SO)
        end.join
      end
    end

    def test_initialize_safe
      assert_raises(SecurityError) do
        Thread.new do
          $SAFE = 2
          DL::Handle.new(LIBC_SO)
        end.join
      end
    end
  end
end
