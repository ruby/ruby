begin
  require_relative 'helper'
  require 'fiddle/cparser'
rescue LoadError
end

module Fiddle
  class TestCParser < TestCase
    include CParser

    def test_char_ctype
      assert_equal(TYPE_CHAR, parse_ctype('char'))
      assert_equal(TYPE_CHAR, parse_ctype('signed char'))
      assert_equal(-TYPE_CHAR, parse_ctype('unsigned char'))
    end

    def test_short_ctype
      assert_equal(TYPE_SHORT, parse_ctype('short'))
      assert_equal(TYPE_SHORT, parse_ctype('short int'))
      assert_equal(TYPE_SHORT, parse_ctype('signed short'))
      assert_equal(TYPE_SHORT, parse_ctype('signed short int'))
      assert_equal(-TYPE_SHORT, parse_ctype('unsigned short'))
      assert_equal(-TYPE_SHORT, parse_ctype('unsigned short int'))
    end

    def test_int_ctype
      assert_equal(TYPE_INT, parse_ctype('int'))
      assert_equal(TYPE_INT, parse_ctype('signed int'))
      assert_equal(-TYPE_INT, parse_ctype('uint'))
      assert_equal(-TYPE_INT, parse_ctype('unsigned int'))
    end

    def test_long_ctype
      assert_equal(TYPE_LONG, parse_ctype('long'))
      assert_equal(TYPE_LONG, parse_ctype('long int'))
      assert_equal(TYPE_LONG, parse_ctype('signed long'))
      assert_equal(TYPE_LONG, parse_ctype('signed long int'))
      assert_equal(-TYPE_LONG, parse_ctype('unsigned long'))
      assert_equal(-TYPE_LONG, parse_ctype('unsigned long int'))
    end

    def test_size_t_ctype
      assert_equal(TYPE_SIZE_T, parse_ctype("size_t"))
    end

    def test_ssize_t_ctype
      assert_equal(TYPE_SSIZE_T, parse_ctype("ssize_t"))
    end

    def test_ptrdiff_t_ctype
      assert_equal(TYPE_PTRDIFF_T, parse_ctype("ptrdiff_t"))
    end

    def test_intptr_t_ctype
      assert_equal(TYPE_INTPTR_T, parse_ctype("intptr_t"))
    end

    def test_uintptr_t_ctype
      assert_equal(TYPE_UINTPTR_T, parse_ctype("uintptr_t"))
    end

    def test_struct_basic
      assert_equal [[TYPE_INT, TYPE_CHAR], ['i', 'c']], parse_struct_signature(['int i', 'char c'])
    end

    def test_struct_array
      assert_equal [[[TYPE_CHAR,80],[TYPE_INT,5]], ['buffer','x']], parse_struct_signature(['char buffer[80]', 'int[5] x'])
    end

    def test_struct_array_str
      assert_equal [[[TYPE_CHAR,80],[TYPE_INT,5]], ['buffer','x']], parse_struct_signature('char buffer[80], int[5] x')
    end

    def test_struct_function_pointer
      assert_equal [[TYPE_VOIDP], ['cb']], parse_struct_signature(['void (*cb)(const char*)'])
    end

    def test_struct_function_pointer_str
      assert_equal [[TYPE_VOIDP,TYPE_VOIDP], ['cb', 'data']], parse_struct_signature('void (*cb)(const char*), const char* data')
    end

    def test_struct_string
      assert_equal [[TYPE_INT,TYPE_VOIDP,TYPE_VOIDP], ['x', 'cb', 'name']], parse_struct_signature('int x; void (*cb)(); const char* name')
    end

    def test_signature_basic
      func, ret, args = parse_signature('void func()')
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [], args
    end

    def test_signature_semi
      func, ret, args = parse_signature('void func();')
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [], args
    end

    def test_signature_void_arg
      func, ret, args = parse_signature('void func(void)')
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [], args
    end

    def test_signature_type_args
      types = [
        'char', 'unsigned char',
        'short', 'unsigned short',
        'int', 'unsigned int',
        'long', 'unsigned long',
        'long long', 'unsigned long long',
        'float', 'double',
        'const char*', 'void*',
      ]
      func, ret, args = parse_signature("void func(#{types.join(',')})")
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [
        TYPE_CHAR, -TYPE_CHAR,
        TYPE_SHORT, -TYPE_SHORT,
        TYPE_INT, -TYPE_INT,
        TYPE_LONG, -TYPE_LONG,
        TYPE_LONG_LONG, -TYPE_LONG_LONG,
        TYPE_FLOAT, TYPE_DOUBLE,
        TYPE_VOIDP, TYPE_VOIDP,
      ], args
    end

    def test_signature_single_variable
      func, ret, args = parse_signature('void func(int x)')
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [TYPE_INT], args
    end

    def test_signature_multiple_variables
      func, ret, args = parse_signature('void func(int x, const char* s)')
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [TYPE_INT, TYPE_VOIDP], args
    end

    def test_signature_array_variable
      func, ret, args = parse_signature('void func(int x[], int y[40])')
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [TYPE_VOIDP, TYPE_VOIDP], args
    end

    def test_signature_function_pointer
      func, ret, args = parse_signature('int func(int (*sum)(int x, int y), int x, int y)')
      assert_equal 'func', func
      assert_equal TYPE_INT, ret
      assert_equal [TYPE_VOIDP, TYPE_INT, TYPE_INT], args
    end

    def test_signature_return_pointer
      func, ret, args = parse_signature('void* malloc(size_t)')
      assert_equal 'malloc', func
      assert_equal TYPE_VOIDP, ret
      assert_equal [TYPE_SIZE_T], args
    end

    def test_signature_return_array
      func, ret, args = parse_signature('int (*func())[32]')
      assert_equal 'func', func
      assert_equal TYPE_VOIDP, ret
      assert_equal [], args
    end

    def test_signature_return_array_with_args
      func, ret, args = parse_signature('int (*func(const char* s))[]')
      assert_equal 'func', func
      assert_equal TYPE_VOIDP, ret
      assert_equal [TYPE_VOIDP], args
    end

    def test_signature_return_function_pointer
      func, ret, args = parse_signature('int (*func())(int x, int y)')
      assert_equal 'func', func
      assert_equal TYPE_VOIDP, ret
      assert_equal [], args
    end

    def test_signature_return_function_pointer_with_args
      func, ret, args = parse_signature('int (*func(int z))(int x, int y)')
      assert_equal 'func', func
      assert_equal TYPE_VOIDP, ret
      assert_equal [TYPE_INT], args
    end
  end
end if defined?(Fiddle)
