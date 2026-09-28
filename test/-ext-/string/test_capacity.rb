# frozen_string_literal: true
require 'test/unit'
require '-test-/string'
require 'rbconfig/sizeof'
require 'objspace'

class Test_StringCapacity < Test::Unit::TestCase
  def test_capacity_embedded
    assert_equal GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE] - embed_header_size - 1, capa('foo')
    assert_equal max_embed_len, capa('1' * max_embed_len)
    assert_equal max_embed_len, capa('1' * (max_embed_len - 1))
  end

  def test_capacity_shared
    sym = ("a" * GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]).to_sym
    assert_equal 0, capa(sym.to_s)
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
    s << "a" * GC::INTERNAL_CONSTANTS[:BASE_SLOT_SIZE]
    s.freeze
    assert_equal(s.length, capa(s))
  end

  def test_capacity_fstring
    s = String.new("a" * max_embed_len, capacity: max_embed_len * 3)
    s << "fstring capacity"
    s = -s
    assert_equal(s.length, capa(s))
  end

  def test_encode_bang_capacity_with_multibyte_terminator
    s = smallest_slot_utf16le_string
    assert(Bug::String.cstr_embedded?(s))

    s.encode!("UTF-8")

    # The UTF-8 form no longer fits in the slot so the buffer is on heap.
    refute(Bug::String.cstr_embedded?(s))

    # and sized precisely
    assert_equal(s.bytesize, capa(s))
  end

  private

  def capa(str)
    Bug::String.capacity(str)
  end

  # A UTF-16LE string that fills the smallest slot, so that its UTF-8 form
  # (1.5x as long) cannot stay embedded.
  def smallest_slot_utf16le_string
    embed_capa = pool_slot_size(0) - embed_header_size
    str = ("\u{30AF}" * ((embed_capa - 2) / 2)).encode("UTF-16LE").b
    str.force_encoding("UTF-16LE")
    str
  end

  def embed_header_size
    3 * RbConfig::SIZEOF['void*']
  end

  def pool_slot_size(_idx = 0)
    Integer(ObjectSpace.dump("")[/"slot_size":(\d+)/, 1])
  end

  def max_embed_len
    GC::INTERNAL_CONSTANTS[:RVARGC_MAX_ALLOCATE_SIZE] - embed_header_size - 1
  end
end
