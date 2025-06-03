# frozen_string_literal: true
require 'test/unit'
require '-test-/string'
require 'rbconfig/sizeof'

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

  private

  def capa(str)
    Bug::String.capacity(str)
  end

  def embed_header_size
    GC::INTERNAL_CONSTANTS[:RBASIC_SIZE] + RbConfig::SIZEOF['void*']
  end

  def max_embed_len
    GC::INTERNAL_CONSTANTS[:RVARGC_MAX_ALLOCATE_SIZE] - embed_header_size - 1
  end
end
