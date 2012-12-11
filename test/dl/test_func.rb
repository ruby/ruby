require_relative 'test_base'
require 'dl/func'

module DL
  class TestFunc < TestBase
    def test_name
      f = Function.new(CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy'),
                       [TYPE_VOIDP, TYPE_VOIDP])
      assert_equal 'strcpy', f.name
    end

    def test_name_with_block
      begin
        cb = Function.new(CFunc.new(0, TYPE_INT, '<callback>qsort'),
                          [TYPE_VOIDP, TYPE_VOIDP]){|x,y| CPtr.new(x)[0] <=> CPtr.new(y)[0]}
        assert_equal('<callback>qsort', cb.name)
      ensure
        cb.unbind if cb # max number of callbacks is limited to MAX_CALLBACK
      end
    end

    def test_bound
      f = Function.new(CFunc.new(0, TYPE_INT, 'test'), [TYPE_INT, TYPE_INT])
      assert_equal false, f.bound?
      begin
        f.bind { |x,y| x + y }
        assert_equal true, f.bound?
      ensure
        f.unbind # max number of callbacks is limited to MAX_CALLBACK
      end
    end

    def test_bound_for_callback_closure
      begin
        f = Function.new(CFunc.new(0, TYPE_INT, 'test'),
                         [TYPE_INT, TYPE_INT]) { |x,y| x + y }
        assert_equal true, f.bound?
      ensure
        f.unbind if f # max number of callbacks is limited to MAX_CALLBACK
      end
    end

    def test_unbind
      f = Function.new(CFunc.new(0, TYPE_INT, 'test'), [TYPE_INT, TYPE_INT])
      begin
        f.bind { |x, y| x + y }
        assert_nothing_raised { f.unbind }
        assert_equal false, f.bound?
        # unbind() after unbind() should not raise error
        assert_nothing_raised { f.unbind }
      ensure
        f.unbind # max number of callbacks is limited to MAX_CALLBACK
      end
    end

    def test_unbind_normal_function
      f = Function.new(CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy'),
                       [TYPE_VOIDP, TYPE_VOIDP])
      assert_nothing_raised { f.unbind }
      assert_equal false, f.bound?
      # unbind() after unbind() should not raise error
      assert_nothing_raised { f.unbind }
    end

    def test_bind
      f = Function.new(CFunc.new(0, TYPE_INT, 'test'), [TYPE_INT, TYPE_INT])
      begin
        assert_nothing_raised {
          f.bind { |x, y| x + y }
        }
        assert_equal 579, f.call(123, 456)
      ensure
        f.unbind # max number of callbacks is limited to MAX_CALLBACK
      end
    end

    def test_to_i
      cfunc = CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy')
      f = Function.new(cfunc, [TYPE_VOIDP, TYPE_VOIDP])
      assert_equal cfunc.to_i, f.to_i
    end

    def test_random
      f = Function.new(CFunc.new(@libc['srand'], TYPE_VOID, 'srand'),
                       [-TYPE_LONG])
      assert_nil f.call(10)
    end

    def test_sinf
      return if /x86_64/ =~ RUBY_PLATFORM
      begin
        f = Function.new(CFunc.new(@libm['sinf'], TYPE_FLOAT, 'sinf'),
                         [TYPE_FLOAT])
      rescue DL::DLError
        skip "libm may not have sinf()"
      end
      assert_in_delta 1.0, f.call(90 * Math::PI / 180), 0.0001
    end

    def test_sin
      return if /x86_64/ =~ RUBY_PLATFORM
      f = Function.new(CFunc.new(@libm['sin'], TYPE_DOUBLE, 'sin'),
                       [TYPE_DOUBLE])
      assert_in_delta 1.0, f.call(90 * Math::PI / 180), 0.0001
    end

    def test_strcpy()
      f = Function.new(CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy'),
                       [TYPE_VOIDP, TYPE_VOIDP])
      buff = "000"
      str = f.call(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    end

    def test_string()
      stress, GC.stress = GC.stress, true
      f = Function.new(CFunc.new(@libc['strcpy'], TYPE_VOIDP, 'strcpy'),
                       [TYPE_VOIDP, TYPE_VOIDP])
      buff = "000"
      str = f.call(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    ensure
      GC.stress = stress
    end

    def test_isdigit()
      f = Function.new(CFunc.new(@libc['isdigit'], TYPE_INT, 'isdigit'),
                       [TYPE_INT])
      r1 = f.call(?1.ord)
      r2 = f.call(?2.ord)
      rr = f.call(?r.ord)
      assert_positive(r1)
      assert_positive(r2)
      assert_zero(rr)
    end

    def test_atof()
      f = Function.new(CFunc.new(@libc['atof'], TYPE_DOUBLE, 'atof'),
                       [TYPE_VOIDP])
      r = f.call("12.34")
      assert_match(12.00..13.00, r)
    end

    def test_strtod()
      f = Function.new(CFunc.new(@libc['strtod'], TYPE_DOUBLE, 'strtod'),
                       [TYPE_VOIDP, TYPE_VOIDP])
      buff1 = CPtr["12.34"]
      buff2 = buff1 + 4
      r = f.call(buff1, - buff2)
      assert_in_delta(12.34, r, 0.001)
    end

    def test_qsort1()
      begin
        cb = Function.new(CFunc.new(0, TYPE_INT, '<callback>qsort'),
                          [TYPE_VOIDP, TYPE_VOIDP]){|x,y| CPtr.new(x)[0] <=> CPtr.new(y)[0]}
        qsort = Function.new(CFunc.new(@libc['qsort'], TYPE_VOID, 'qsort'),
                             [TYPE_VOIDP, TYPE_SIZE_T, TYPE_SIZE_T, TYPE_VOIDP])
        buff = "9341"
        qsort.call(buff, buff.size, 1, cb)
        assert_equal("1349", buff)

        bug4929 = '[ruby-core:37395]'
        buff = "9341"
        EnvUtil.under_gc_stress {qsort.call(buff, buff.size, 1, cb)}
        assert_equal("1349", buff, bug4929)
      ensure
        cb.unbind if cb # max number of callbacks is limited to MAX_CALLBACK
      end
    end

    def test_qsort2()
      cb = TempFunction.new(CFunc.new(0, TYPE_INT, '<callback>qsort'),
                               [TYPE_VOIDP, TYPE_VOIDP])
      qsort = Function.new(CFunc.new(@libc['qsort'], TYPE_VOID, 'qsort'),
                           [TYPE_VOIDP, TYPE_SIZE_T, TYPE_SIZE_T, TYPE_VOIDP])
      buff = "9341"
      qsort.call(buff, buff.size, 1, cb){|x,y| CPtr.new(x)[0] <=> CPtr.new(y)[0]}
      assert_equal("1349", buff)
    end
  end
end
