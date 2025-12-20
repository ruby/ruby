require 'test/unit'
require '-test-/string'
require 'objspace'
require 'json'

class Test_StringAdopt < Test::Unit::TestCase
  def test_adopts_the_pointer
    str = "foo"
    capa = 500
    adopted_str = Bug::String.rb_enc_str_adopt(str, str.bytesize, capa, Encoding::UTF_8)

    assert_equal str, adopted_str
    assert_equal Encoding::UTF_8, adopted_str.encoding

    info = JSON.parse(ObjectSpace.dump(adopted_str))
    assert_equal capa - 1, info["capacity"]
  end

  def test_null_encoding
    str = Bug::String.rb_enc_str_adopt("foo", 3, 4, nil)
    assert_equal Encoding::BINARY, str.encoding
  end

  def test_negative_length
    assert_raise ArgumentError do
      Bug::String.rb_enc_str_adopt("foo", -1, 100, nil)
    end
  end

  def test_too_small_capa
    assert_raise ArgumentError do
      Bug::String.rb_enc_str_adopt("foo", 3, 3, nil)
    end
  end

  def test_no_memory_leak
    code = '.times { Bug::String.rb_enc_str_adopt(str, str.bytesize, str.bytesize, nil) rescue nil }'
    assert_no_memory_leak(%w(-r-test-/string),
                          "str = 'a' * 10_000",
                          "100_000#{code}",
                          rss: true)
  end
end
