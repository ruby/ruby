begin
  require_relative 'helper'
  require_relative '../ruby/envutil'
rescue LoadError
end

module Fiddle
  class TestPointer < TestCase
    def dlwrap arg
      Fiddle.dlwrap arg
    end

    include Test::Unit::Assertions

    def test_cptr_to_int
      null = Fiddle::NULL
      assert_equal(null.to_i, null.to_int)
    end

    def test_malloc_free_func_int
      free = Fiddle::Function.new(Fiddle::RUBY_FREE, [TYPE_VOIDP], TYPE_VOID)
      assert_equal free.to_i, Fiddle::RUBY_FREE.to_i

      ptr  = Pointer.malloc(10, free.to_i)
      assert_equal 10, ptr.size
      assert_equal free.to_i, ptr.free.to_i
    end

    def test_malloc_free_func
      free = Fiddle::Function.new(Fiddle::RUBY_FREE, [TYPE_VOIDP], TYPE_VOID)

      ptr  = Pointer.malloc(10, free)
      assert_equal 10, ptr.size
      assert_equal free.to_i, ptr.free.to_i
    end

    def test_to_str
      str = "hello world"
      ptr = Pointer[str]

      assert_equal 3, ptr.to_str(3).length
      assert_equal str, ptr.to_str

      ptr[5] = 0
      assert_equal "hello\0world", ptr.to_str
    end

    def test_to_s
      str = "hello world"
      ptr = Pointer[str]

      assert_equal 3, ptr.to_s(3).length
      assert_equal str, ptr.to_s

      ptr[5] = 0
      assert_equal 'hello', ptr.to_s
    end

    def test_minus
      str = "hello world"
      ptr = Pointer[str]
      assert_equal ptr.to_s, (ptr + 3 - 3).to_s
    end

    # TODO: what if the pointer size is 0?  raise an exception? do we care?
    def test_plus
      str = "hello world"
      ptr = Pointer[str]
      new_str = ptr + 3
      assert_equal 'lo world', new_str.to_s
    end

    def test_inspect
      ptr = Pointer.new(0)
      inspect = ptr.inspect
      assert_match(/size=#{ptr.size}/, inspect)
      assert_match(/free=#{sprintf("%#x", ptr.free.to_i)}/, inspect)
      assert_match(/ptr=#{sprintf("%#x", ptr.to_i)}/, inspect)
    end

    def test_to_ptr_string
      str = "hello world"
      ptr = Pointer[str]
      assert ptr.tainted?, 'pointer should be tainted'
      assert_equal str.length, ptr.size
      assert_equal 'hello', ptr[0,5]
    end

    def test_to_ptr_io
      buf = Pointer.malloc(10)
      File.open(__FILE__, 'r') do |f|
        ptr = Pointer.to_ptr f
        fread = Function.new(@libc['fread'],
                             [TYPE_VOIDP, TYPE_INT, TYPE_INT, TYPE_VOIDP],
                             TYPE_INT)
        fread.call(buf.to_i, Fiddle::SIZEOF_CHAR, buf.size - 1, ptr.to_i)
      end

      File.open(__FILE__, 'r') do |f|
        assert_equal f.read(9), buf.to_s
      end
    end

    def test_to_ptr_with_ptr
      ptr = Pointer.new 0
      ptr2 = Pointer.to_ptr Struct.new(:to_ptr).new(ptr)
      assert_equal ptr, ptr2

      assert_raises(Fiddle::DLError) do
        Pointer.to_ptr Struct.new(:to_ptr).new(nil)
      end
    end

    def test_to_ptr_with_num
      ptr = Pointer.new 0
      assert_equal ptr, Pointer[0]
    end

    def test_equals
      ptr   = Pointer.new 0
      ptr2  = Pointer.new 0
      assert_equal ptr2, ptr
    end

    def test_not_equals
      ptr = Pointer.new 0
      refute_equal 10, ptr, '10 should not equal the pointer'
    end

    def test_cmp
      ptr = Pointer.new 0
      assert_nil(ptr <=> 10, '10 should not be comparable')
    end

    def test_ref_ptr
      ary = [0,1,2,4,5]
      addr = Pointer.new(dlwrap(ary))
      assert_equal addr.to_i, addr.ref.ptr.to_i

      assert_equal addr.to_i, (+ (- addr)).to_i
    end

    def test_to_value
      ary = [0,1,2,4,5]
      addr = Pointer.new(dlwrap(ary))
      assert_equal ary, addr.to_value
    end

    def test_free
      ptr = Pointer.malloc(4)
      assert_nil ptr.free
    end

    def test_free=
      assert_normal_exit(<<-"End", '[ruby-dev:39269]')
        require 'fiddle'
        Fiddle::LIBC_SO = #{Fiddle::LIBC_SO.dump}
        Fiddle::LIBM_SO = #{Fiddle::LIBM_SO.dump}
        include Fiddle
        @libc = dlopen(LIBC_SO)
        @libm = dlopen(LIBM_SO)
        free = Fiddle::Function.new(Fiddle::RUBY_FREE, [TYPE_VOIDP], TYPE_VOID)
        ptr = Fiddle::Pointer.malloc(4)
        ptr.free = free
        free.ptr
        ptr.free.ptr
      End

      free = Function.new(Fiddle::RUBY_FREE, [TYPE_VOIDP], TYPE_VOID)
      ptr = Pointer.malloc(4)
      ptr.free = free

      assert_equal free.ptr, ptr.free.ptr
    end

    def test_null?
      ptr = Pointer.new(0)
      assert ptr.null?
    end

    def test_size
      ptr = Pointer.malloc(4)
      assert_equal 4, ptr.size
      Fiddle.free ptr.to_i
    end

    def test_size=
      ptr = Pointer.malloc(4)
      ptr.size = 10
      assert_equal 10, ptr.size
      Fiddle.free ptr.to_i
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
      ptr = Pointer[str]
      check.call(str, ptr)

      str[0] = "c"
      assert_equal 'c'.ord, ptr[0] = "c".ord
      check.call(str, ptr)

      str[0,2] = "aa"
      assert_equal 'aa', ptr[0,2] = "aa"
      check.call(str, ptr)

      ptr2 = Pointer['cdeeee']
      str[0,2] = "cd"
      assert_equal ptr2, ptr[0,2] = ptr2
      check.call(str, ptr)

      ptr3 = Pointer['vvvv']
      str[0,2] = "vv"
      assert_equal ptr3.to_i, ptr[0,2] = ptr3.to_i
      check.call(str, ptr)
    end

    def test_null_pointer
      nullpo = Pointer.new(0)
      assert_raise(DLError) {nullpo[0]}
      assert_raise(DLError) {nullpo[0] = 1}
    end

    def test_no_memory_leak
      assert_no_memory_leak(%w[-W0 -rfiddle.so], '', '100_000.times {Fiddle::Pointer.allocate}', rss: true)
    end
  end
end if defined?(Fiddle)
