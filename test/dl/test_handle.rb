require 'test_base'

module DL
  class TestHandle < TestBase
    def test_to_i
      handle = DL::Handle.new(LIBC_SO)
      assert handle.to_i
    end

    def test_static_sym_secure
      assert_raises(SecurityError) do
        Thread.new do
          $SAFE = 2
          DL::Handle.sym('calloc')
        end.join
      end
    end

    def test_static_sym_unknown
      assert_raises(DL::DLError) { DL::Handle.sym('fooo') }
      assert_raises(DL::DLError) { DL::Handle['fooo'] }
    end

    def test_static_sym
      assert DL::Handle.sym('dlopen')
      assert_equal DL::Handle.sym('dlopen'), DL::Handle['dlopen']
    end

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

    def test_initialize_noargs
      handle = DL::Handle.new
      assert handle['rb_str_new']
    end

    def test_initialize_flags
      handle = DL::Handle.new(LIBC_SO, DL::RTLD_LAZY | DL::RTLD_GLOBAL)
      assert handle['calloc']
    end

    def test_enable_close
      handle = DL::Handle.new(LIBC_SO)
      assert !handle.close_enabled?, 'close is enabled'

      handle.enable_close
      assert handle.close_enabled?, 'close is not enabled'
    end

    def test_disable_close
      handle = DL::Handle.new(LIBC_SO)

      handle.enable_close
      assert handle.close_enabled?, 'close is enabled'
      handle.disable_close
      assert !handle.close_enabled?, 'close is enabled'
    end

    def test_NEXT
      handle = DL::Handle::NEXT
      assert handle['malloc']
    end

    def test_DEFAULT
      handle = DL::Handle::DEFAULT
      assert handle['malloc']
    end
  end
end
