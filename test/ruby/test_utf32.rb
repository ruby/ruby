require 'test/unit'

class TestUTF32 < Test::Unit::TestCase
  def encdump(str)
    d = str.dump
    if /\.force_encoding\("[A-Za-z0-9.:_+-]*"\)\z/ =~ d
      d
    else
      "#{d}.force_encoding(#{str.encoding.name.dump})"
    end
  end

  def assert_str_equal(expected, actual, message=nil)
    full_message = build_message(message, <<EOT)
#{encdump expected} expected but not equal to
#{encdump actual}.
EOT
    assert_block(full_message) { expected == actual }
  end

  def test_substr
    assert_str_equal(
      "abcdefgh".force_encoding("utf-32be"),
      "abcdefgh".force_encoding("utf-32be")[0,3])
  end
end

