# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
end

module Fiddle
  class TestFunction < Fiddle::TestCase
    def setup
      super
      Fiddle.last_error = nil
      if WINDOWS
        Fiddle.win32_last_error = nil
        Fiddle.win32_last_socket_error = nil
      end
    end

    def test_default_abi
      func = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE)
      assert_equal Function::DEFAULT, func.abi
    end

    def test_name
      func = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE, name: 'sin')
      assert_equal 'sin', func.name
    end

    def test_need_gvl?
      libruby = Fiddle.dlopen(nil)
      rb_str_dup = Function.new(libruby['rb_str_dup'],
                                [:voidp],
                                :voidp,
                                need_gvl: true)
      assert(rb_str_dup.need_gvl?)
      assert_equal('Hello',
                   Fiddle.dlunwrap(rb_str_dup.call(Fiddle.dlwrap('Hello'))))
    end

    def test_argument_errors
      assert_raise(TypeError) do
        Function.new(@libm['sin'], TYPE_DOUBLE, TYPE_DOUBLE)
      end

      assert_raise(TypeError) do
        Function.new(@libm['sin'], ['foo'], TYPE_DOUBLE)
      end

      assert_raise(TypeError) do
        Function.new(@libm['sin'], [TYPE_DOUBLE], 'foo')
      end
    end

    def test_argument_type_conversion
      type = Struct.new(:int, :call_count) do
        def initialize(int)
          super(int, 0)
        end
        def to_int
          raise "exhausted" if (self.call_count += 1) > 1
          self.int
        end
      end
      type_arg = type.new(TYPE_DOUBLE)
      type_result = type.new(TYPE_DOUBLE)
      assert_nothing_raised(RuntimeError) do
        Function.new(@libm['sin'], [type_arg], type_result)
      end
      assert_equal(1, type_arg.call_count)
      assert_equal(1, type_result.call_count)
    end

    def test_call
      func = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE)
      assert_in_delta 1.0, func.call(90 * Math::PI / 180), 0.0001
    end

    def test_argument_count
      closure = Class.new(Closure) {
        def call one
          10 + one
        end
      }.new(TYPE_INT, [TYPE_INT])
      func = Function.new(closure, [TYPE_INT], TYPE_INT)

      assert_raise(ArgumentError) do
        func.call(1,2,3)
      end
      assert_raise(ArgumentError) do
        func.call
      end
    end

    def test_last_error
      func = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)

      assert_nil Fiddle.last_error
      func.call(+"000", "123")
      refute_nil Fiddle.last_error
    end

    if WINDOWS
      def test_win32_last_error
        kernel32 = Fiddle.dlopen("kernel32")
        args = [kernel32["SetLastError"], [-TYPE_LONG], TYPE_VOID]
        args << Function::STDCALL if Function.const_defined?(:STDCALL)
        set_last_error = Function.new(*args)
        assert_nil(Fiddle.win32_last_error)
        n = 1 << 29 | 1
        set_last_error.call(n)
        assert_equal(n, Fiddle.win32_last_error)
      end

      def test_win32_last_socket_error
        ws2_32 = Fiddle.dlopen("ws2_32")
        args = [ws2_32["WSASetLastError"], [TYPE_INT], TYPE_VOID]
        args << Function::STDCALL if Function.const_defined?(:STDCALL)
        wsa_set_last_error = Function.new(*args)
        assert_nil(Fiddle.win32_last_socket_error)
        n = 1 << 29 | 1
        wsa_set_last_error.call(n)
        assert_equal(n, Fiddle.win32_last_socket_error)
      end
    end

    def test_strcpy
      f = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)
      buff = +"000"
      str = f.call(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    end

    def call_proc(string_to_copy)
      buff = +"000"
      str = yield(buff, string_to_copy)
      [buff, str]
    end

    def test_function_as_proc
      f = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)
      buff, str = call_proc("123", &f)
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    end

    def test_function_as_method
      f = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)
      klass = Class.new do
        define_singleton_method(:strcpy, &f)
      end
      buff = +"000"
      str = klass.strcpy(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    end

    def test_nogvl_poll
      # XXX hack to quiet down CI errors on EINTR from r64353
      # [ruby-core:88360] [Misc #14937]
      # Making pipes (and sockets) non-blocking by default would allow
      # us to get rid of POSIX timers / timer pthread
      # https://bugs.ruby-lang.org/issues/14968
      IO.pipe { |r,w| IO.select([r], [w]) }
      begin
        poll = @libc['poll']
      rescue Fiddle::DLError
        omit 'poll(2) not available'
      end
      f = Function.new(poll, [TYPE_VOIDP, TYPE_INT, TYPE_INT], TYPE_INT)

      msec = 200
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      th = Thread.new { f.call(nil, 0, msec) }
      n1 = f.call(nil, 0, msec)
      n2 = th.value
      t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      assert_in_delta(msec, t1 - t0, 180, 'slept amount of time')
      assert_equal(0, n1, perror("poll(2) in main-thread"))
      assert_equal(0, n2, perror("poll(2) in sub-thread"))
    end

    def test_no_memory_leak
      if respond_to?(:assert_nothing_leaked_memory)
        rb_obj_frozen_p_symbol = Fiddle.dlopen(nil)["rb_obj_frozen_p"]
        rb_obj_frozen_p = Fiddle::Function.new(rb_obj_frozen_p_symbol,
                                               [Fiddle::TYPE_UINTPTR_T],
                                               Fiddle::TYPE_UINTPTR_T)
        a = "a"
        n_tries = 100_000
        n_tries.times do
          begin
            a + 1
          rescue TypeError
          end
        end
        n_arguments = 1
        sizeof_fiddle_generic = Fiddle::SIZEOF_VOIDP # Rough
        size_per_try =
          (sizeof_fiddle_generic * n_arguments) +
          (Fiddle::SIZEOF_VOIDP * (n_arguments + 1))
        assert_nothing_leaked_memory(size_per_try * n_tries) do
          n_tries.times do
            begin
              rb_obj_frozen_p.call(a)
            rescue TypeError
            end
          end
        end
      else
        prep = 'r = Fiddle::Function.new(Fiddle.dlopen(nil)["rb_obj_frozen_p"], [Fiddle::TYPE_UINTPTR_T], Fiddle::TYPE_UINTPTR_T); a = "a"'
        code = 'begin r.call(a); rescue TypeError; end'
        assert_no_memory_leak(%w[-W0 -rfiddle], "#{prep}\n1000.times{#{code}}", "10_000.times {#{code}}", limit: 1.2)
      end
    end

    private

    def perror(m)
      proc do
        if e = Fiddle.last_error
          m = "#{m}: #{SystemCallError.new(e).message}"
        end
        m
      end
    end
  end
end if defined?(Fiddle)
