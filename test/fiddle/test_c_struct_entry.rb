# frozen_string_literal: true
begin
  require_relative 'helper'
  require 'fiddle/struct'
rescue LoadError
end

module Fiddle
  class TestCStructEntity < TestCase
    def test_class_size
      types = [TYPE_DOUBLE, TYPE_CHAR, TYPE_DOUBLE, TYPE_BOOL]

      size = CStructEntity.size types

      alignments = types.map { |type| PackInfo::ALIGN_MAP[type] }

      expected = PackInfo.align 0, alignments[0]
      expected += PackInfo::SIZE_MAP[TYPE_DOUBLE]

      expected = PackInfo.align expected, alignments[1]
      expected += PackInfo::SIZE_MAP[TYPE_CHAR]

      expected = PackInfo.align expected, alignments[2]
      expected += PackInfo::SIZE_MAP[TYPE_DOUBLE]

      expected = PackInfo.align expected, alignments[3]
      expected += PackInfo::SIZE_MAP[TYPE_BOOL]

      expected = PackInfo.align expected, alignments.max

      assert_equal expected, size
    end

    def test_class_size_with_count
      size = CStructEntity.size([[TYPE_DOUBLE, 2], [TYPE_CHAR, 20]])

      types = [TYPE_DOUBLE, TYPE_CHAR]
      alignments = types.map { |type| PackInfo::ALIGN_MAP[type] }

      expected = PackInfo.align 0, alignments[0]
      expected += PackInfo::SIZE_MAP[TYPE_DOUBLE] * 2

      expected = PackInfo.align expected, alignments[1]
      expected += PackInfo::SIZE_MAP[TYPE_CHAR] * 20

      expected = PackInfo.align expected, alignments.max

      assert_equal expected, size
    end

    def test_set_ctypes
      CStructEntity.malloc([TYPE_INT, TYPE_LONG], Fiddle::RUBY_FREE) do |struct|
        struct.assign_names %w[int long]

        # this test is roundabout because the stored ctypes are not accessible
        struct['long'] = 1
        struct['int'] = 2

        assert_equal 1, struct['long']
        assert_equal 2, struct['int']
      end
    end

    def test_aref_pointer_array
      CStructEntity.malloc([[TYPE_VOIDP, 2]], Fiddle::RUBY_FREE) do |team|
        team.assign_names(["names"])
        Fiddle::Pointer.malloc(6, Fiddle::RUBY_FREE) do |alice|
          alice[0, 6] = "Alice\0"
          Fiddle::Pointer.malloc(4, Fiddle::RUBY_FREE) do |bob|
            bob[0, 4] = "Bob\0"
            team["names"] = [alice, bob]
            assert_equal(["Alice", "Bob"], team["names"].map(&:to_s))
          end
        end
      end
    end

    def test_aref_pointer
      CStructEntity.malloc([TYPE_VOIDP], Fiddle::RUBY_FREE) do |user|
        user.assign_names(["name"])
        Fiddle::Pointer.malloc(6, Fiddle::RUBY_FREE) do |alice|
          alice[0, 6] = "Alice\0"
          user["name"] = alice
          assert_equal("Alice", user["name"].to_s)
        end
      end
    end

    def test_new_double_free
      types = [TYPE_INT]
      Pointer.malloc(CStructEntity.size(types), Fiddle::RUBY_FREE) do |pointer|
        assert_raise ArgumentError do
          CStructEntity.new(pointer, types, Fiddle::RUBY_FREE)
        end
      end
    end

    def test_malloc_block
      escaped_struct = nil
      returned = CStructEntity.malloc([TYPE_INT], Fiddle::RUBY_FREE) do |struct|
        assert_equal Fiddle::SIZEOF_INT, struct.size
        assert_equal Fiddle::RUBY_FREE, struct.free.to_i
        escaped_struct = struct
        :returned
      end
      assert_equal :returned, returned
      assert escaped_struct.freed?
    end

    def test_malloc_block_no_free
      assert_raise ArgumentError do
        CStructEntity.malloc([TYPE_INT]) { |struct| }
      end
    end

    def test_free
      struct = CStructEntity.malloc([TYPE_INT])
      begin
        assert_nil struct.free
      ensure
        Fiddle.free struct
      end
    end

    def test_free_with_func
      struct = CStructEntity.malloc([TYPE_INT], Fiddle::RUBY_FREE)
      refute struct.freed?
      struct.call_free
      assert struct.freed?
      struct.call_free                 # you can safely run it again
      assert struct.freed?
      GC.start                         # you can safely run the GC routine
      assert struct.freed?
    end

    def test_free_with_no_func
      struct = CStructEntity.malloc([TYPE_INT])
      refute struct.freed?
      struct.call_free
      refute struct.freed?
      struct.call_free                 # you can safely run it again
      refute struct.freed?
    end

    def test_freed?
      struct = CStructEntity.malloc([TYPE_INT], Fiddle::RUBY_FREE)
      refute struct.freed?
      struct.call_free
      assert struct.freed?
    end

    def test_null?
      struct = CStructEntity.malloc([TYPE_INT], Fiddle::RUBY_FREE)
      refute struct.null?
    end

    def test_size
      CStructEntity.malloc([TYPE_INT], Fiddle::RUBY_FREE) do |struct|
        assert_equal Fiddle::SIZEOF_INT, struct.size
      end
    end

    def test_size=
      CStructEntity.malloc([TYPE_INT], Fiddle::RUBY_FREE) do |struct|
        assert_raise NoMethodError do
          struct.size = 1
        end
      end
    end
  end
end if defined?(Fiddle)
