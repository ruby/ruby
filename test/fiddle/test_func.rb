# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
end

module Fiddle
  class TestFunc < TestCase
    def test_random
      f = Function.new(@libc['srand'], [-TYPE_LONG], TYPE_VOID)
      assert_nil f.call(10)
    end

    def test_sinf
      begin
        f = Function.new(@libm['sinf'], [TYPE_FLOAT], TYPE_FLOAT)
      rescue Fiddle::DLError
        skip "libm may not have sinf()"
      end
      assert_in_delta 1.0, f.call(90 * Math::PI / 180), 0.0001
    end

    def test_sin
      f = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE)
      assert_in_delta 1.0, f.call(90 * Math::PI / 180), 0.0001
    end

    def test_string
      stress, GC.stress = GC.stress, true
      f = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)
      buff = +"000"
      str = f.call(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    ensure
      GC.stress = stress
    end

    def test_isdigit
      f = Function.new(@libc['isdigit'], [TYPE_INT], TYPE_INT)
      r1 = f.call(?1.ord)
      r2 = f.call(?2.ord)
      rr = f.call(?r.ord)
      assert_operator r1, :>, 0
      assert_operator r2, :>, 0
      assert_equal 0, rr
    end

    def test_atof
      f = Function.new(@libc['atof'], [TYPE_VOIDP], TYPE_DOUBLE)
      r = f.call("12.34")
      assert_includes(12.00..13.00, r)
    end

    def test_strtod
      f = Function.new(@libc['strtod'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_DOUBLE)
      buff1 = Pointer["12.34"]
      buff2 = buff1 + 4
      r = f.call(buff1, - buff2)
      assert_in_delta(12.34, r, 0.001)
    end

    def test_qsort1
      cb = Class.new(Closure) {
        def call(x, y)
          Pointer.new(x)[0] <=> Pointer.new(y)[0]
        end
      }.new(TYPE_INT, [TYPE_VOIDP, TYPE_VOIDP])

      qsort = Function.new(@libc['qsort'],
                           [TYPE_VOIDP, TYPE_SIZE_T, TYPE_SIZE_T, TYPE_VOIDP],
                           TYPE_VOID)
      buff = "9341"
      qsort.call(buff, buff.size, 1, cb)
      assert_equal("1349", buff)

      bug4929 = '[ruby-core:37395]'
      buff = "9341"
      EnvUtil.under_gc_stress {qsort.call(buff, buff.size, 1, cb)}
      assert_equal("1349", buff, bug4929)
    end

    def test_snprintf
      unless Fiddle.const_defined?("TYPE_VARIADIC")
        skip "libffi doesn't support variadic arguments"
      end
      if Fiddle::WINDOWS
        snprintf_name = "_snprintf"
      else
        snprintf_name = "snprintf"
      end
      begin
        snprintf_pointer = @libc[snprintf_name]
      rescue Fiddle::DLError
        skip "Can't find #{snprintf_name}: #{$!.message}"
      end
      snprintf = Function.new(snprintf_pointer,
                              [
                                TYPE_VOIDP,
                                TYPE_SIZE_T,
                                TYPE_CONST_STRING,
                                TYPE_VARIADIC,
                              ],
                              TYPE_INT)
      output_buffer = " " * 1024
      output = Pointer[output_buffer]

      written = snprintf.call(output,
                              output.size,
                              "int: %d, string: %.*s, const string: %s\n",
                              TYPE_INT, -29,
                              TYPE_INT, 4,
                              TYPE_VOIDP, "Hello",
                              TYPE_CONST_STRING, "World")
      assert_equal("int: -29, string: Hell, const string: World\n",
                   output_buffer[0, written])

      string_like_class = Class.new do
        def initialize(string)
          @string = string
        end

        def to_str
          @string
        end
      end
      written = snprintf.call(output,
                              output.size,
                              "string: %.*s, const string: %s, uint: %u\n",
                              TYPE_INT, 2,
                              TYPE_VOIDP, "Hello",
                              TYPE_CONST_STRING, string_like_class.new("World"),
                              TYPE_INT, 29)
      assert_equal("string: He, const string: World, uint: 29\n",
                   output_buffer[0, written])
    end
  end
end if defined?(Fiddle)
