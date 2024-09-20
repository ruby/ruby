# frozen_string_literal: false
require 'test/unit'
require "-test-/string"

class Test_StrSetLen < Test::Unit::TestCase
  def setup
    # Make string long enough so that it is not embedded
    @range_end = ("0".ord + GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]).chr
    @s0 = [*"0"..@range_end].join("").freeze
    @s1 = Bug::String.new(@s0)
  end

  def teardown
    orig = [*"0"..@range_end].join("")
    assert_equal(orig, @s0)
  end

  def test_non_shared
    @s1.modify!
    assert_equal("012", @s1.set_len(3))
  end

  def test_shared
    assert_raise(RuntimeError) {
      @s1.set_len(3)
    }
  end

  def test_capacity_equals_to_new_size
    bug12757 = "[ruby-core:77257] [Bug #12757]"
    # fill to ensure capacity does not decrease with force_encoding
    str = Bug::String.new("\x00" * 128, capacity: 128)
    str.force_encoding("UTF-32BE")
    assert_equal 128, Bug::String.capacity(str)
    assert_equal 127, str.set_len(127).bytesize, bug12757
  end

  def test_coderange_after_append
    u = -"\u3042"
    str = Bug::String.new(encoding: Encoding::UTF_8)
    bsize = u.bytesize
    str.append(u)
    assert_equal 0, str.bytesize
    str.set_len(bsize)
    assert_equal bsize, str.bytesize
    assert_predicate str, :valid_encoding?
    assert_not_predicate str, :ascii_only?
    assert_equal u, str
  end

  def test_coderange_after_trunc
    u = -"\u3042"
    bsize = u.bytesize
    str = Bug::String.new(u)
    str.set_len(bsize - 1)
    assert_equal bsize - 1, str.bytesize
    assert_not_predicate str, :valid_encoding?
    assert_not_predicate str, :ascii_only?
    str.append(u.byteslice(-1))
    str.set_len(bsize)
    assert_equal bsize, str.bytesize
    assert_predicate str, :valid_encoding?
    assert_not_predicate str, :ascii_only?
    assert_equal u, str
  end

  def test_valid_encoding_after_resized
    s = "\0\0".force_encoding(Encoding::UTF_16BE)
    str = Bug::String.new(s)
    assert_predicate str, :valid_encoding?
    str.resize(1)
    assert_not_predicate str, :valid_encoding?
    str.resize(2)
    assert_predicate str, :valid_encoding?
    str.resize(3)
    assert_not_predicate str, :valid_encoding?

    s = "\xDB\x00\xDC\x00".force_encoding(Encoding::UTF_16BE)
    str = Bug::String.new(s)
    assert_predicate str, :valid_encoding?
    str.resize(2)
    assert_not_predicate str, :valid_encoding?
  end
end
