# coding: utf-8
require 'test/unit'

class BinaryUTF8CompatTest < Test::Unit::TestCase
  def setup
    @binary_mb = 'héllø'.force_encoding('binary')
    @utf8_mb   = 'héllø'.force_encoding('utf-8')
    @binary_as = 'hello'.force_encoding('binary')
    @utf8_as   = 'hello'.force_encoding('utf-8')
  end

  def test_encode_utf8_to_binary
    assert_nothing_raised do
      @utf8_mb.encode('binary')
    end
  end

  def test_encode_binary_to_utf8
    assert_nothing_raised do
      @binary_mb.encode('utf-8')
    end
  end

  def test_invalid_byte_seq
    email = "\xD0\xEE\xEC\xE0\xF8\xEA\xE0@MyAcerPC.(none)".force_encoding('UTF-8')
    assert_nothing_raised do
      email.strip
      email.split("\0")
      email.split(/\s+/)
    end
  end

  def test_equal_contents
    assert_equal @binary_mb, @utf8_mb
  end

  def test_hash_lookups
    hash = {}
    hash[@binary_mb] = 1
    assert_equal 1, hash[@utf8_mb]
  end

  def test_match_binary_regexp
    assert_nothing_raised do
      assert_equal 0, Regexp.new(@binary_mb) =~ @utf8_mb
    end
  end

  def test_match_utf8_regexp
    assert_nothing_raised do
      assert_equal 0, Regexp.new(@utf8_mb) =~ @binary_mb
    end
  end

  def test_add_binary
    ret = @binary_mb + @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_mb + @binary_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_as + @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_as + @binary_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
  end

  def test_add_utf8
    ret = @utf8_mb + @utf8_mb
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_mb + @utf8_as
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_as + @utf8_mb
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_as + @utf8_as
    assert_equal Encoding::UTF_8, ret.encoding
  end

  def test_add_utf8_plus_7bit
    ret = @binary_as + @utf8_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_as + @utf8_mb
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_as + @binary_as
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_mb + @binary_as
    assert_equal Encoding::UTF_8, ret.encoding
  end

  def test_add_8bit_plus_utf8
    ret = @binary_mb + @utf8_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_mb + @utf8_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @utf8_mb + @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @utf8_as + @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
  end

  def test_concat_binary
    ret = @binary_mb.dup << @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_mb.dup << @binary_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_as.dup << @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_as.dup << @binary_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
  end

  def test_concat_utf8
    ret = @utf8_mb.dup << @utf8_mb
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_mb.dup << @utf8_as
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_as.dup << @utf8_mb
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_as.dup << @utf8_as
    assert_equal Encoding::UTF_8, ret.encoding
  end

  def test_concat_utf8_and_7bit
    ret = @binary_as.dup << @utf8_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_as.dup << @utf8_mb
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_as.dup << @binary_as
    assert_equal Encoding::UTF_8, ret.encoding
    ret = @utf8_mb.dup << @binary_as
    assert_equal Encoding::UTF_8, ret.encoding
  end

  def test_concat_8bit_and_utf8
    ret = @binary_mb.dup << @utf8_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @binary_mb.dup << @utf8_as
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @utf8_mb.dup << @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
    ret = @utf8_as.dup << @binary_mb
    assert_equal Encoding::ASCII_8BIT, ret.encoding
  end
end
