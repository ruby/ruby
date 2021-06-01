# coding: US-ASCII
# frozen_string_literal: true
begin
  require_relative 'helper'
  require 'fiddle/import'
rescue LoadError
end

module Fiddle
  module LIBC
    extend Importer
    dlload LIBC_SO, LIBM_SO

    typealias 'string', 'char*'
    typealias 'FILE*', 'void*'

    extern "void *strcpy(char*, char*)"
    extern "int isdigit(int)"
    extern "double atof(string)"
    extern "unsigned long strtoul(char*, char **, int)"
    extern "int qsort(void*, unsigned long, unsigned long, void*)"
    extern "int fprintf(FILE*, char*)" rescue nil
    extern "int gettimeofday(timeval*, timezone*)" rescue nil

    BoundQsortCallback = bind("void *bound_qsort_callback(void*, void*)"){|ptr1,ptr2| ptr1[0] <=> ptr2[0]}
    Timeval = struct [
      "long tv_sec",
      "long tv_usec",
    ]
    Timezone = struct [
      "int tz_minuteswest",
      "int tz_dsttime",
    ]
    MyStruct = struct [
      "short num[5]",
      "char c",
      "unsigned char buff[7]",
    ]
    StructNestedStruct = struct [
      {
        "vertices[2]" => {
          position: ["float x", "float y", "float z"],
          texcoord: ["float u", "float v"]
        },
        object: ["int id", "void *user_data"],
      },
      "int id"
    ]
    UnionNestedStruct = union [
      {
        keyboard: [
          'unsigned int state',
          'char key'
        ],
        mouse: [
          'unsigned int button',
          'unsigned short x',
          'unsigned short y'
        ]
      }
    ]

    CallCallback = bind("void call_callback(void*, void*)"){ | ptr1, ptr2|
      f = Function.new(ptr1.to_i, [TYPE_VOIDP], TYPE_VOID)
      f.call(ptr2)
    }
  end

  class TestImport < TestCase
    def test_ensure_call_dlload
      err = assert_raise(RuntimeError) do
        Class.new do
          extend Importer
          extern "void *strcpy(char*, char*)"
        end
      end
      assert_match(/call dlload before/, err.message)
    end

    def test_struct_memory_access()
      # check memory operations performed directly on struct
      Fiddle::Importer.struct(['int id']).malloc(Fiddle::RUBY_FREE) do |my_struct|
        my_struct[0, Fiddle::SIZEOF_INT] = "\x01".b * Fiddle::SIZEOF_INT
        assert_equal 0x01010101, my_struct.id

        my_struct.id = 0
        assert_equal "\x00".b * Fiddle::SIZEOF_INT, my_struct[0, Fiddle::SIZEOF_INT]
      end
    end

    def test_struct_ptr_array_subscript_multiarg()
      # check memory operations performed on struct#to_ptr
      Fiddle::Importer.struct([ 'int x' ]).malloc(Fiddle::RUBY_FREE) do |struct|
        ptr = struct.to_ptr

        struct.x = 0x02020202
        assert_equal("\x02".b * Fiddle::SIZEOF_INT, ptr[0, Fiddle::SIZEOF_INT])

        ptr[0, Fiddle::SIZEOF_INT] = "\x01".b * Fiddle::SIZEOF_INT
        assert_equal 0x01010101, struct.x
      end
    end

    def test_malloc()
      LIBC::Timeval.malloc(Fiddle::RUBY_FREE) do |s1|
        LIBC::Timeval.malloc(Fiddle::RUBY_FREE) do |s2|
          refute_equal(s1.to_ptr.to_i, s2.to_ptr.to_i)
        end
      end
    end

    def test_sizeof()
      assert_equal(SIZEOF_VOIDP, LIBC.sizeof("FILE*"))
      assert_equal(LIBC::MyStruct.size(), LIBC.sizeof(LIBC::MyStruct))
      LIBC::MyStruct.malloc(Fiddle::RUBY_FREE) do |my_struct|
        assert_equal(LIBC::MyStruct.size(), LIBC.sizeof(my_struct))
      end
      assert_equal(SIZEOF_LONG_LONG, LIBC.sizeof("long long")) if defined?(SIZEOF_LONG_LONG)
      assert_equal(LIBC::StructNestedStruct.size(), LIBC.sizeof(LIBC::StructNestedStruct))
    end

    Fiddle.constants.grep(/\ATYPE_(?!VOID|VARIADIC\z)(.*)/) do
      type = $&
      const_type_name = $1
      size = Fiddle.const_get("SIZEOF_#{const_type_name}")
      if const_type_name == "CONST_STRING"
        name = "const_string"
        type_name = "const char*"
      else
        name = $1.sub(/P\z/,"*").gsub(/_(?!T\z)/, " ").downcase
        type_name = name
      end
      define_method("test_sizeof_#{name}") do
        assert_equal(size, Fiddle::Importer.sizeof(type_name), type)
      end
    end

    def test_unsigned_result()
      d = (2 ** 31) + 1

      r = LIBC.strtoul(d.to_s, 0, 0)
      assert_equal(d, r)
    end

    def test_io()
      if( RUBY_PLATFORM != BUILD_RUBY_PLATFORM ) || !defined?(LIBC.fprintf)
        return
      end
      io_in,io_out = IO.pipe()
      LIBC.fprintf(io_out, "hello")
      io_out.flush()
      io_out.close()
      str = io_in.read()
      io_in.close()
      assert_equal("hello", str)
    end

    def test_value()
      i = LIBC.value('int', 2)
      assert_equal(2, i.value)

      d = LIBC.value('double', 2.0)
      assert_equal(2.0, d.value)

      ary = LIBC.value('int[3]', [0,1,2])
      assert_equal([0,1,2], ary.value)
    end

    def test_struct_array_assignment()
      Fiddle::Importer.struct(["unsigned int stages[3]"]).malloc(Fiddle::RUBY_FREE) do |instance|
        instance.stages[0] = 1024
        instance.stages[1] = 10
        instance.stages[2] = 100
        assert_equal 1024, instance.stages[0]
        assert_equal 10, instance.stages[1]
        assert_equal 100, instance.stages[2]
        assert_equal [1024, 10, 100].pack(Fiddle::PackInfo::PACK_MAP[-Fiddle::TYPE_INT] * 3),
                    instance.to_ptr[0, 3 * Fiddle::SIZEOF_INT]
        assert_raise(IndexError) { instance.stages[-1] = 5 }
        assert_raise(IndexError) { instance.stages[3] = 5 }
      end
    end

    def test_nested_struct_reusing_other_structs()
      position_struct = Fiddle::Importer.struct(['float x', 'float y', 'float z'])
      texcoord_struct = Fiddle::Importer.struct(['float u', 'float v'])
      vertex_struct   = Fiddle::Importer.struct(position: position_struct, texcoord: texcoord_struct)
      mesh_struct     = Fiddle::Importer.struct([
                                                  {
                                                    "vertices[2]" => vertex_struct,
                                                    object: [
                                                      "int id",
                                                      "void *user_data",
                                                    ],
                                                  },
                                                  "int id",
                                                ])
      assert_equal LIBC::StructNestedStruct.size, mesh_struct.size


      keyboard_event_struct = Fiddle::Importer.struct(['unsigned int state', 'char key'])
      mouse_event_struct    = Fiddle::Importer.struct(['unsigned int button', 'unsigned short x', 'unsigned short y'])
      event_union           = Fiddle::Importer.union([{ keboard: keyboard_event_struct, mouse: mouse_event_struct}])
      assert_equal LIBC::UnionNestedStruct.size, event_union.size
    end

    def test_nested_struct_alignment_is_not_its_size()
      inner = Fiddle::Importer.struct(['int x', 'int y', 'int z', 'int w'])
      outer = Fiddle::Importer.struct(['char a', { 'nested' => inner }, 'char b'])
      outer.malloc(Fiddle::RUBY_FREE) do |instance|
        offset = instance.to_ptr.instance_variable_get(:"@offset")
        assert_equal Fiddle::SIZEOF_INT * 5, offset.last
        assert_equal Fiddle::SIZEOF_INT * 6, outer.size
        assert_equal instance.to_ptr.size, outer.size
      end
    end

    def test_struct_nested_struct_members()
      LIBC::StructNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        Fiddle::Pointer.malloc(24, Fiddle::RUBY_FREE) do |user_data|
          s.vertices[0].position.x = 1
          s.vertices[0].position.y = 2
          s.vertices[0].position.z = 3
          s.vertices[0].texcoord.u = 4
          s.vertices[0].texcoord.v = 5
          s.vertices[1].position.x = 6
          s.vertices[1].position.y = 7
          s.vertices[1].position.z = 8
          s.vertices[1].texcoord.u = 9
          s.vertices[1].texcoord.v = 10
          s.object.id              = 100
          s.object.user_data       = user_data
          s.id                     = 101
          assert_equal({
                         "vertices" => [
                           {
                             "position" => {
                               "x" => 1,
                               "y" => 2,
                               "z" => 3,
                             },
                             "texcoord" => {
                               "u" => 4,
                               "v" => 5,
                             },
                           },
                           {
                             "position" => {
                               "x" => 6,
                               "y" => 7,
                               "z" => 8,
                             },
                             "texcoord" => {
                               "u" => 9,
                               "v" => 10,
                             },
                           },
                         ],
                         "object" => {
                           "id" => 100,
                           "user_data" => user_data,
                         },
                         "id" => 101,
                       },
                       s.to_h)
        end
      end
    end

    def test_union_nested_struct_members()
      LIBC::UnionNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        s.keyboard.state = 100
        s.keyboard.key   = 101
        assert_equal(100, s.mouse.button)
        refute_equal(  0, s.mouse.x)
      end
    end

    def test_struct_nested_struct_replace_array_element()
      LIBC::StructNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        s.vertices[0].position.x = 5

        vertex_struct = Fiddle::Importer.struct [{
          position: ["float x", "float y", "float z"],
          texcoord: ["float u", "float v"]
        }]
        vertex_struct.malloc(Fiddle::RUBY_FREE) do |vertex|
          vertex.position.x = 100
          s.vertices[0] = vertex

          # make sure element was copied by value, but things like memory address
          # should not be changed
          assert_equal(100,              s.vertices[0].position.x)
          refute_equal(vertex.object_id, s.vertices[0].object_id)
          refute_equal(vertex.to_ptr,    s.vertices[0].to_ptr)
        end
      end
    end

    def test_struct_nested_struct_replace_array_element_nil()
      LIBC::StructNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        s.vertices[0].position.x = 5
        s.vertices[0] = nil
        assert_equal({
                       "position" => {
                         "x" => 0.0,
                         "y" => 0.0,
                         "z" => 0.0,
                       },
                       "texcoord" => {
                         "u" => 0.0,
                         "v" => 0.0,
                       },
                     },
                     s.vertices[0].to_h)
      end
    end

    def test_struct_nested_struct_replace_array_element_hash()
      LIBC::StructNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        s.vertices[0] = {
          position: {
            x: 10,
            y: 100,
          }
        }
        assert_equal({
                       "position" => {
                         "x" => 10.0,
                         "y" => 100.0,
                         "z" => 0.0,
                       },
                       "texcoord" => {
                         "u" => 0.0,
                         "v" => 0.0,
                       },
                     },
                     s.vertices[0].to_h)
      end
    end

    def test_struct_nested_struct_replace_entire_array()
      LIBC::StructNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        vertex_struct = Fiddle::Importer.struct [{
          position: ["float x", "float y", "float z"],
          texcoord: ["float u", "float v"]
        }]

        vertex_struct.malloc(Fiddle::RUBY_FREE) do |same0|
          vertex_struct.malloc(Fiddle::RUBY_FREE) do |same1|
            same = [same0, same1]
            same[0].position.x = 1; same[1].position.x = 6
            same[0].position.y = 2; same[1].position.y = 7
            same[0].position.z = 3; same[1].position.z = 8
            same[0].texcoord.u = 4; same[1].texcoord.u = 9
            same[0].texcoord.v = 5; same[1].texcoord.v = 10
            s.vertices = same
            assert_equal([
                           {
                             "position" => {
                               "x" => 1.0,
                               "y" => 2.0,
                               "z" => 3.0,
                             },
                             "texcoord" => {
                               "u" => 4.0,
                               "v" => 5.0,
                             },
                           },
                           {
                             "position" => {
                               "x" => 6.0,
                               "y" => 7.0,
                               "z" => 8.0,
                             },
                             "texcoord" => {
                               "u" => 9.0,
                               "v" => 10.0,
                             },
                           }
                         ],
                         s.vertices.collect(&:to_h))
          end
        end
      end
    end

    def test_struct_nested_struct_replace_entire_array_with_different_struct()
      LIBC::StructNestedStruct.malloc(Fiddle::RUBY_FREE) do |s|
        different_struct_same_size = Fiddle::Importer.struct [{
          a: ['float i', 'float j', 'float k'],
          b: ['float l', 'float m']
        }]

        different_struct_same_size.malloc(Fiddle::RUBY_FREE) do |different0|
          different_struct_same_size.malloc(Fiddle::RUBY_FREE) do |different1|
            different = [different0, different1]
            different[0].a.i = 11; different[1].a.i = 16
            different[0].a.j = 12; different[1].a.j = 17
            different[0].a.k = 13; different[1].a.k = 18
            different[0].b.l = 14; different[1].b.l = 19
            different[0].b.m = 15; different[1].b.m = 20
            s.vertices[0][0, s.vertices[0].class.size] = different[0].to_ptr
            s.vertices[1][0, s.vertices[1].class.size] = different[1].to_ptr
            assert_equal([
                           {
                             "position" => {
                               "x" => 11.0,
                               "y" => 12.0,
                               "z" => 13.0,
                             },
                             "texcoord" => {
                               "u" => 14.0,
                               "v" => 15.0,
                             },
                           },
                           {
                             "position" => {
                               "x" => 16.0,
                               "y" => 17.0,
                               "z" => 18.0,
                             },
                             "texcoord" => {
                               "u" => 19.0,
                               "v" => 20.0,
                             },
                           }
                         ],
                         s.vertices.collect(&:to_h))
          end
        end
      end
    end

    def test_struct()
      LIBC::MyStruct.malloc(Fiddle::RUBY_FREE) do |s|
        s.num = [0,1,2,3,4]
        s.c = ?a.ord
        s.buff = "012345\377"
        assert_equal([0,1,2,3,4], s.num)
        assert_equal(?a.ord, s.c)
        assert_equal([?0.ord,?1.ord,?2.ord,?3.ord,?4.ord,?5.ord,?\377.ord], s.buff)
      end
    end

    def test_gettimeofday()
      if( defined?(LIBC.gettimeofday) )
        LIBC::Timeval.malloc(Fiddle::RUBY_FREE) do |timeval|
          LIBC::Timezone.malloc(Fiddle::RUBY_FREE) do |timezone|
            LIBC.gettimeofday(timeval, timezone)
          end
          cur = Time.now()
          assert(cur.to_i - 2 <= timeval.tv_sec && timeval.tv_sec <= cur.to_i)
        end
      end
    end

    def test_strcpy()
      buff = +"000"
      str = LIBC.strcpy(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    end

    def test_isdigit
      r1 = LIBC.isdigit(?1.ord)
      r2 = LIBC.isdigit(?2.ord)
      rr = LIBC.isdigit(?r.ord)
      assert_operator(r1, :>, 0)
      assert_operator(r2, :>, 0)
      assert_equal(0, rr)
    end

    def test_atof
      r = LIBC.atof("12.34")
      assert_includes(12.00..13.00, r)
    end
  end
end if defined?(Fiddle)
