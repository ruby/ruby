begin
  require_relative 'helper'
rescue LoadError
end

module Fiddle
  class TestHandle < TestCase
    include Fiddle

    include Test::Unit::Assertions

    def test_safe_handle_open
      t = Thread.new do
        $SAFE = 1
        Fiddle::Handle.new(LIBC_SO.taint)
      end
      assert_raise(SecurityError) { t.value }
    end

    def test_safe_function_lookup
      t = Thread.new do
        h = Fiddle::Handle.new(LIBC_SO)
        $SAFE = 1
        h["qsort".taint]
      end
      assert_raise(SecurityError) { t.value }
    end

    def test_to_i
      handle = Fiddle::Handle.new(LIBC_SO)
      assert_kind_of Integer, handle.to_i
    end

    def test_static_sym_secure
      assert_raises(SecurityError) do
        Thread.new do
          $SAFE = 2
          Fiddle::Handle.sym('calloc')
        end.join
      end
    end

    def test_static_sym_unknown
      assert_raises(DLError) { Fiddle::Handle.sym('fooo') }
      assert_raises(DLError) { Fiddle::Handle['fooo'] }
    end

    def test_static_sym
      skip "Fiddle::Handle.sym is not supported" if /mswin|mingw/ =~ RUBY_PLATFORM
      begin
        # Linux / Darwin / FreeBSD
        refute_nil Fiddle::Handle.sym('dlopen')
        assert_equal Fiddle::Handle.sym('dlopen'), Fiddle::Handle['dlopen']
      rescue
        # NetBSD
        require '-test-/dln/empty'
        refute_nil Fiddle::Handle.sym('Init_empty')
        assert_equal Fiddle::Handle.sym('Init_empty'), Fiddle::Handle['Init_empty']
      end
    end

    def test_sym_closed_handle
      handle = Fiddle::Handle.new(LIBC_SO)
      handle.close
      assert_raises(DLError) { handle.sym("calloc") }
      assert_raises(DLError) { handle["calloc"] }
    end

    def test_sym_unknown
      handle = Fiddle::Handle.new(LIBC_SO)
      assert_raises(DLError) { handle.sym('fooo') }
      assert_raises(DLError) { handle['fooo'] }
    end

    def test_sym_with_bad_args
      handle = Handle.new(LIBC_SO)
      assert_raises(TypeError) { handle.sym(nil) }
      assert_raises(TypeError) { handle[nil] }
    end

    def test_sym_secure
      assert_raises(SecurityError) do
        Thread.new do
          $SAFE = 2
          handle = Handle.new(LIBC_SO)
          handle.sym('calloc')
        end.join
      end
    end

    def test_sym
      handle = Handle.new(LIBC_SO)
      refute_nil handle.sym('calloc')
      refute_nil handle['calloc']
    end

    def test_handle_close
      handle = Handle.new(LIBC_SO)
      assert_equal 0, handle.close
    end

    def test_handle_close_twice
      handle = Handle.new(LIBC_SO)
      handle.close
      assert_raises(DLError) do
        handle.close
      end
    end

    def test_dlopen_returns_handle
      assert_instance_of Handle, dlopen(LIBC_SO)
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
          Handle.new(LIBC_SO)
        end.join
      end
    end

    def test_initialize_noargs
      handle = Handle.new
      refute_nil handle['rb_str_new']
    end

    def test_initialize_flags
      handle = Handle.new(LIBC_SO, RTLD_LAZY | RTLD_GLOBAL)
      refute_nil handle['calloc']
    end

    def test_enable_close
      handle = Handle.new(LIBC_SO)
      assert !handle.close_enabled?, 'close is enabled'

      handle.enable_close
      assert handle.close_enabled?, 'close is not enabled'
    end

    def test_disable_close
      handle = Handle.new(LIBC_SO)

      handle.enable_close
      assert handle.close_enabled?, 'close is enabled'
      handle.disable_close
      assert !handle.close_enabled?, 'close is enabled'
    end

    def test_NEXT
      begin
        # Linux / Darwin
        #
        # There are two special pseudo-handles, RTLD_DEFAULT and RTLD_NEXT.  The  former  will  find
        # the  first  occurrence  of the desired symbol using the default library search order.  The
        # latter will find the next occurrence of a function in the search order after  the  current
        # library.   This  allows  one  to  provide  a  wrapper  around a function in another shared
        # library.
        # --- Ubuntu Linux 8.04 dlsym(3)
        handle = Handle::NEXT
        refute_nil handle['malloc']
      rescue
        # BSD
        #
        # If dlsym() is called with the special handle RTLD_NEXT, then the search
        # for the symbol is limited to the shared objects which were loaded after
        # the one issuing the call to dlsym().  Thus, if the function is called
        # from the main program, all the shared libraries are searched.  If it is
        # called from a shared library, all subsequent shared libraries are
        # searched.  RTLD_NEXT is useful for implementing wrappers around library
        # functions.  For example, a wrapper function getpid() could access the
        # "real" getpid() with dlsym(RTLD_NEXT, "getpid").  (Actually, the dlfunc()
        # interface, below, should be used, since getpid() is a function and not a
        # data object.)
        # --- FreeBSD 8.0 dlsym(3)
        require '-test-/dln/empty'
        handle = Handle::NEXT
        refute_nil handle['Init_empty']
      end
    end unless /mswin|mingw/ =~ RUBY_PLATFORM

    def test_DEFAULT
      skip "Handle::DEFAULT is not supported" if /mswin|mingw/ =~ RUBY_PLATFORM
      handle = Handle::DEFAULT
      refute_nil handle['malloc']
    end unless /mswin|mingw/ =~ RUBY_PLATFORM

    def test_dlerror
      # FreeBSD (at least 7.2 to 7.2) calls nsdispatch(3) when it calls
      # getaddrinfo(3). And nsdispatch(3) doesn't call dlerror(3) even if
      # it calls _nss_cache_cycle_prevention_function with dlsym(3).
      # So our Fiddle::Handle#sym must call dlerror(3) before call dlsym.
      # In general uses of dlerror(3) should call it before use it.
      require 'socket'
      Socket.gethostbyname("localhost")
      Fiddle.dlopen("/lib/libc.so.7").sym('strcpy')
    end if /freebsd/=~ RUBY_PLATFORM

    def test_no_memory_leak
      assert_no_memory_leak(%w[-W0 -rfiddle.so], '', '100_000.times {Fiddle::Handle.allocate}; GC.start', rss: true)
    end
  end
end if defined?(Fiddle)
