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
    assert_wchars_term_char(" a") {|s| s.lstrip!}
  end

  def test_wchar_rstrip!
    assert_wchars_term_char("a ") {|s| s.rstrip!}
  end

  def test_wchar_chop!
    assert_wchars_term_char("a\n") {|s| s.chop!}
  end

  def test_wchar_chomp!
    assert_wchars_term_char("a\n") {|s| s.chomp!}
  end

  def test_wchar_aset
    assert_wchars_term_char("a"*30) {|s| s[29,1] = ""}
  end

  def test_wchar_sub!
    assert_wchars_term_char("foobar") {|s| s.sub!(/#{"foo".encode(s.encoding)}/, "")}
  end

  def test_wchar_delete!
    assert_wchars_term_char("foobar") {|s| s.delete!("ao".encode(s.encoding))}
  end

  def test_wchar_squeeze!
    assert_wchars_term_char("foo!") {|s| s.squeeze!}
  end

  def test_wchar_tr!
    assert_wchars_term_char("\u{3042}foobar") {|s|
      enc = s.encoding
      s.tr!("\u{3042}".encode(enc), "c".encode(enc))
    }
  end

  def test_wchar_tr_s!
    assert_wchars_term_char("\u{3042}foobar") {|s|
      enc = s.encoding
      s.tr_s!("\u{3042}".encode(enc), "c".encode(enc))
    }
  end

  def test_embedded_from_heap
    gh821 = "[GH-821]"
    embedded_string = "abcdefghi"
    string = embedded_string.gsub("efg", "123")
    {}[string] = 1
    non_terminated = "#{string}#{nil}"
    assert_nil(Bug::String.cstr_term_char(non_terminated), gh821)

    result = {}
    WCHARS.map do |enc|
      embedded_string = "ab".encode(enc)
      string = embedded_string.gsub("b".encode(enc), "1".encode(enc))
      {}[string] = 1
      non_terminated = "#{string}#{nil}"
      c = Bug::String.cstr_term_char(non_terminated)
      result[enc] = c if c
    end
    assert_empty(result, gh821)
  end

  def assert_wchars_term_char(str)
    result = {}
    WCHARS.map do |enc|
      s = Bug::String.new(str.encode(enc))
      yield s
      c = s.cstr_term_char
      result[enc] = c if c
    end
    assert_empty(result)
  end
end
