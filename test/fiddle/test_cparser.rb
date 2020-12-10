# frozen_string_literal: true
begin
  require_relative 'helper'
  require 'fiddle/cparser'
  require 'fiddle/import'
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

    def test_undefined_ctype
      assert_raise(DLError) { parse_ctype('DWORD') }
    end

    def test_undefined_ctype_with_type_alias
      assert_equal(-TYPE_LONG, parse_ctype('DWORD', {"DWORD" => "unsigned long"}))
    end

    def expand_struct_types(types)
      types.collect do |type|
        case type
        when Class
          [expand_struct_types(type.types)]
        when Array
          [expand_struct_types([type[0]])[0][0], type[1]]
        else
          type
        end
      end
    end

    def test_struct_basic
      assert_equal [[TYPE_INT, TYPE_CHAR], ['i', 'c']], parse_struct_signature(['int i', 'char c'])
    end

    def test_struct_array
      assert_equal [[[TYPE_CHAR,80],[TYPE_INT,5]], ['buffer','x']], parse_struct_signature(['char buffer[80]', 'int[5] x'])
    end

    def test_struct_nested_struct
      types, members = parse_struct_signature([
                                                'int x',
                                                {inner: ['int i', 'char c']},
                                              ])
      assert_equal([[TYPE_INT, [[TYPE_INT, TYPE_CHAR]]],
                    ['x', ['inner', ['i', 'c']]]],
                   [expand_struct_types(types),
                    members])
    end

    def test_struct_nested_defined_struct
      inner = Fiddle::Importer.struct(['int i', 'char c'])
      assert_equal([[TYPE_INT, inner],
                    ['x', ['inner', ['i', 'c']]]],
                   parse_struct_signature([
                                            'int x',
                                            {inner: inner},
                                          ]))
    end

    def test_struct_double_nested_struct
      types, members = parse_struct_signature([
                                                'int x',
                                                {
                                                  outer: [
                                                    'int y',
                                                    {inner: ['int i', 'char c']},
                                                  ],
                                                },
                                              ])
      assert_equal([[TYPE_INT, [[TYPE_INT, [[TYPE_INT, TYPE_CHAR]]]]],
                    ['x', ['outer', ['y', ['inner', ['i', 'c']]]]]],
                   [expand_struct_types(types),
                    members])
    end

    def test_struct_nested_struct_array
      types, members = parse_struct_signature([
                                                'int x',
                                                {
                                                  'inner[2]' => [
                                                    'int i',
                                                    'char c',
                                                  ],
                                                },
                                              ])
      assert_equal([[TYPE_INT, [[TYPE_INT, TYPE_CHAR], 2]],
                    ['x', ['inner', ['i', 'c']]]],
                   [expand_struct_types(types),
                    members])
    end

    def test_struct_double_nested_struct_inner_array
      types, members = parse_struct_signature(outer: [
                                                'int x',
                                                {
                                                  'inner[2]' => [
                                                    'int i',
                                                    'char c',
                                                  ],
                                                },
                                              ])
      assert_equal([[[[TYPE_INT, [[TYPE_INT, TYPE_CHAR], 2]]]],
                    [['outer', ['x', ['inner', ['i', 'c']]]]]],
                   [expand_struct_types(types),
                    members])
    end

    def test_struct_double_nested_struct_outer_array
      types, members = parse_struct_signature([
                                                'int x',
                                                {
                                                  'outer[2]' => {
                                                    inner: [
                                                      'int i',
                                                      'char c',
                                                    ],
                                                  },
                                                },
                                              ])
      assert_equal([[TYPE_INT, [[[[TYPE_INT, TYPE_CHAR]]], 2]],
                    ['x', ['outer', [['inner', ['i', 'c']]]]]],
                   [expand_struct_types(types),
                    members])
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

    def test_struct_undefined
      assert_raise(DLError) { parse_struct_signature(['int i', 'DWORD cb']) }
    end

    def test_struct_undefined_with_type_alias
      assert_equal [[TYPE_INT,-TYPE_LONG], ['i', 'cb']], parse_struct_signature(['int i', 'DWORD cb'], {"DWORD" => "unsigned long"})
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
        defined?(TYPE_LONG_LONG) && \
        [
        'long long', 'unsigned long long',
        ],
        'float', 'double',
        'const char*', 'void*',
      ].flatten.compact
      func, ret, args = parse_signature("void func(#{types.join(',')})")
      assert_equal 'func', func
      assert_equal TYPE_VOID, ret
      assert_equal [
        TYPE_CHAR, -TYPE_CHAR,
        TYPE_SHORT, -TYPE_SHORT,
        TYPE_INT, -TYPE_INT,
        TYPE_LONG, -TYPE_LONG,
        defined?(TYPE_LONG_LONG) && \
        [
        TYPE_LONG_LONG, -TYPE_LONG_LONG,
        ],
        TYPE_FLOAT, TYPE_DOUBLE,
        TYPE_VOIDP, TYPE_VOIDP,
      ].flatten.compact, args
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

    def test_signature_variadic_arguments
      unless Fiddle.const_defined?("TYPE_VARIADIC")
        skip "libffi doesn't support variadic arguments"
      end
      assert_equal([
                     "printf",
                     TYPE_INT,
                     [TYPE_VOIDP, TYPE_VARIADIC],
                   ],
                   parse_signature('int printf(const char *format, ...)'))
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
