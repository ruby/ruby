require 'test/unit'

class TestUTF16 < Test::Unit::TestCase
  def encdump(str)
    d = str.dump
    if /\.force_encoding\("[A-Za-z0-9.:_+-]*"\)\z/ =~ d
      d
    else
      "#{d}.force_encoding(#{str.encoding.name.dump})"
    end
  end

  def enccall(recv, meth, *args)
    desc = ''
    if String === recv
      desc << encdump(recv)
    else
      desc << recv.inspect
    end
    desc << '.' << meth.to_s
    if !args.empty?
      desc << '('
      args.each_with_index {|a, i|
        desc << ',' if 0 < i
        if String === a
          desc << encdump(a)
        else
          desc << a.inspect
        end
      }
      desc << ')'
    end
    result = nil
    assert_nothing_raised(desc) {
      result = recv.send(meth, *args)
    }
    result
  end

  def assert_str_equal(expected, actual, message=nil)
    full_message = build_message(message, <<EOT)
#{encdump expected} expected but not equal to
#{encdump actual}.
EOT
    assert_block(full_message) { expected == actual }
  end

  # tests start

  def test_utf16be_valid_encoding
    s = "\xd8\x00\xd8\x00".force_encoding("utf-16be")
    assert_equal(false, s.valid_encoding?, "#{encdump s}.valid_encoding?")
  end

  def test_strftime
    s = "aa".force_encoding("utf-16be")
    assert_raise(ArgumentError, "Time.now.strftime(#{encdump s})") { Time.now.strftime(s) }
  end

  def test_intern
    s = "aaaa".force_encoding("utf-16be")
    assert_equal(s.encoding, s.intern.to_s.encoding, "#{encdump s}.intern.to_s.encoding")
  end

  def test_compatible
    s1 = "aa".force_encoding("utf-16be")
    s2 = "z".force_encoding("us-ascii")
    assert_nil(Encoding.compatible?(s1, s2), "Encoding.compatible?(#{encdump s1}, #{encdump s2})")
  end

  def test_end_with
    s1 = "ab".force_encoding("utf-16be")
    s2 = "b".force_encoding("utf-16be")
    assert_equal(false, s1.end_with?(s2), "#{encdump s1}.end_with?(#{encdump s2})")
  end

  def test_hex
    s1 = "f\0f\0".force_encoding("utf-16le")
    assert_equal(255, s1.hex, "#{encdump s1}.hex")
  end

  def test_count
    s1 = "aa".force_encoding("utf-16be")
    s2 = "aa"
    assert_raise(ArgumentError, "#{encdump s1}.count(#{encdump s2})") {
      s1.count(s2)
    }
  end

  def test_plus
    s1 = "a".force_encoding("us-ascii")
    s2 = "aa".force_encoding("utf-16be")
    assert_raise(ArgumentError, "#{encdump s1} + #{encdump s2}") {
      s1 + s2
    }
  end

  def test_encoding_find
    assert_raise(ArgumentError) {
      Encoding.find("utf-8".force_encoding("utf-16be"))
    }
  end

  def test_interpolation
    s = "aa".force_encoding("utf-16be")
    assert_raise(ArgumentError, "\"a\#{#{encdump s}}\"") {
      "a#{s}"
    }
  end

  def test_slice!
    enccall("aa".force_encoding("UTF-16BE"), :slice!, -1)
  end

  def test_concat
    s1 = ""
    s2 = "aa".force_encoding("utf-16be")
    assert_raise(ArgumentError, "#{encdump s1} << #{encdump s2}") {
      s1 << s2
    }
  end

  def test_chomp
    s = "\1\n".force_encoding("utf-16be")
    assert_str_equal(s, s.chomp, "#{encdump s}.chomp")
  end

  def test_regexp_union
    enccall(Regexp, :union, "aa".force_encoding("utf-16be"), "bb".force_encoding("utf-16be"))
  end

  def test_empty_regexp
    s = "".force_encoding("utf-16be")
    assert_equal(Encoding.find("utf-16be"), Regexp.new(s).encoding,
                "Regexp.new(#{encdump s}).encoding")
  end
end
