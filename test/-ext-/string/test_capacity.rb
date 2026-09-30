# frozen_string_literal: true
require 'test/unit'
require '-test-/string'
require 'rbconfig/sizeof'
require 'objspace'

class Test_StringCapacity < Test::Unit::TestCase
  def test_capacity_embedded
    assert_equal pool_slot_size(0) - embed_header_size - 1, capa('foo')
    assert_equal max_embed_len, capa('1' * max_embed_len)
    assert_include ((max_embed_len - 1)..max_embed_len), capa('1' * (max_embed_len - 1))
  end

  def test_capacity_shared
    source = ("a" * pool_slot_size(0)).freeze
    assert_equal 0, capa(Bug::String.rb_str_new_shared(source))
  end

  def test_capacity_normal
    assert_equal max_embed_len + 1, capa('1' * (max_embed_len + 1))
    assert_equal max_embed_len + 100, capa('1' * (max_embed_len + 100))
  end

  def test_s_new_capacity
    assert_equal("", String.new(capacity: 1000))
    assert_equal(String, String.new(capacity: 1000).class)
    assert_equal(10_000, capa(String.new(capacity: 10_000)))

    assert_equal("", String.new(capacity: -1000))
    assert_equal(capa(String.new(capacity: -10000)), capa(String.new(capacity: -1000)))
  end

  def test_io_read
    s = String.new(capacity: 1000)
    open(__FILE__) {|f|f.read(1024*1024, s)}
    assert_equal(1024*1024, capa(s))
    open(__FILE__) {|f|s = f.read(1024*1024)}
    assert_operator(capa(s), :<=, s.bytesize+4096)
  end

  def test_literal_capacity
    s = eval(%{
      # frozen_string_literal: true
      "#{"a" * (max_embed_len + 1)}"
    })
    assert_equal(s.length, capa(s))
  end

  def test_capacity_frozen
    s = String.new("I am testing", capacity: 1000)
    s << "a" * pool_slot_size(0)
    s.freeze
    assert_equal(s.length, capa(s))
  end

  def test_capacity_fstring
    s = String.new("a" * max_embed_len, capacity: max_embed_len * 3)
    s << "fstring capacity"
    s = -s
    assert_equal(s.length, capa(s))
  end

  # Temporarily handing a string's buffer over to a frozen shared root
  # (rb_str_tmp_frozen_acquire) uses an internal ASCII-8BIT string.  Use
  # UTF-16LE so that the terminator length of the root differs from the
  # terminator length of the string to verify that releasing the root restores
  # the capacity in the string's own encoding.
  def test_frozen_root_capacity_with_multibyte_terminator
    s = multibyte_terminator_string
    capacity = capa(s)
    assert_operator(capacity, :>=, s.bytesize)

    Bug::String.tmp_frozen_acquire_release(s)

    assert_equal(capacity, capa(s))
  end

  def test_frozen_root_no_embed_capacity_with_multibyte_terminator
    # This approximates heap strings returned by C extensions: non-embedded,
    # not shared, and with an exactly-sized external buffer.
    s = Bug::String.cstr_noembed(multibyte_terminator_string)
    capacity = capa(s)
    assert_operator(capacity, :>=, s.bytesize)

    Bug::String.tmp_frozen_no_embed_acquire_release(s)

    assert_equal(capacity, capa(s))
  end

  private

  def capa(str)
    Bug::String.capacity(str)
  end

  def multibyte_terminator_string
    ("\u{30AF}\u{30FC}\u{30DD}\u{30F3}\u{1F381}" * 100).encode("UTF-16LE")
  end

  def embed_header_size
    GC::INTERNAL_CONSTANTS[:RBASIC_SIZE] + RbConfig::SIZEOF['void*']
  end

  def pool_slot_size(_idx = 0)
    Integer(ObjectSpace.dump("")[/"slot_size":(\d+)/, 1])
  end

  def max_embed_len
    GC::INTERNAL_CONSTANTS[:RVARGC_MAX_ALLOCATE_SIZE] - embed_header_size - 1
  end
end
