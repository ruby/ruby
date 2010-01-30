require 'test_base'

module DL
  class TestHandle < TestBase
    def test_sym_closed_handle
      handle = DL::Handle.new(LIBC_SO)
      handle.close
      assert_raises(DL::DLError) { handle.sym("calloc") }
      assert_raises(DL::DLError) { handle["calloc"] }
    end

    def test_sym_unknown
      handle = DL::Handle.new(LIBC_SO)
      assert_raises(DL::DLError) { handle.sym('fooo') }
      assert_raises(DL::DLError) { handle['fooo'] }
    end

    def test_sym_with_bad_args
      handle = DL::Handle.new(LIBC_SO)
      assert_raises(TypeError) { handle.sym(nil) }
      assert_raises(TypeError) { handle[nil] }
    end

    def test_sym_secure
      assert_raises(SecurityError) do
        Thread.new do
          $SAFE = 2
          handle = DL::Handle.new(LIBC_SO)
          handle.sym('calloc')
        end.join
      end
    end

    def test_sym
      handle = DL::Handle.new(LIBC_SO)
      assert handle.sym('calloc')
      assert handle['calloc']
    end

    def test_handle_close
      handle = DL::Handle.new(LIBC_SO)
      assert_equal 0, handle.close
    end

    def test_handle_close_twice
      handle = DL::Handle.new(LIBC_SO)
      handle.close
      handle.close rescue DL::DLError
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
