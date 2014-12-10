require 'test/unit'
require "-test-/string/string"

class Test_StringCStr < Test::Unit::TestCase
  Bug4319 = '[ruby-dev:43094]'

  def test_embed
    s = Bug::String.new("abcdef")
    s.set_len(3)
    assert_equal(0, s.cstr_term, Bug4319)
  end

  def test_long
    s = Bug::String.new("abcdef")*100000
    assert_equal(0, s.cstr_term, Bug4319)
  end

  WCHARS = [Encoding::UTF_16BE, Encoding::UTF_16LE, Encoding::UTF_32BE, Encoding::UTF_32LE]

  def test_wchar_embed
    WCHARS.each do |enc|
      s = Bug::String.new("\u{4022}a".encode(enc))
      assert_nothing_raised(ArgumentError) {s.cstr_term}
      s.set_len(s.bytesize / 2)
      assert_equal(1, s.size)
      assert_equal(0, s.cstr_term)
    end
  end

  def test_wchar_long
    str = "\u{4022}abcdef"
    n = 100
    len = str.size * n
    WCHARS.each do |enc|
      s = Bug::String.new(str.encode(enc))*n
      assert_nothing_raised(ArgumentError, enc.name) {s.cstr_term}
      s.set_len(s.bytesize / 2)
      assert_equal(len / 2, s.size, enc.name)
      assert_equal(0, s.cstr_term, enc.name)
    end
  end

  def test_wchar_lstrip!
    str = Bug::String.new(" a".encode(Encoding::UTF_16BE))
    str.lstrip!
    assert_nil(str.cstr_term_char)
  end

  def test_wchar_rstrip!
    str = Bug::String.new("a ".encode(Encoding::UTF_16BE))
    str.rstrip!
    assert_nil(str.cstr_term_char)
  end
end
