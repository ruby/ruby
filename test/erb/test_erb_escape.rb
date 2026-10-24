require 'test/unit'
require 'erb'

class TestERBEscape < Test::Unit::TestCase
  def test_html_escape
    assert_equal(" !&quot;\#$%&amp;&#39;()*+,-./0123456789:;&lt;=&gt;?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~",
                 ERB::Util.html_escape(" !\"\#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"))

    assert_equal("", ERB::Util.html_escape(""))
    assert_equal("abc", ERB::Util.html_escape("abc"))
    assert_equal("&lt;&lt;", ERB::Util.html_escape("<\<"))
    assert_equal("&#39;&amp;&quot;&gt;&lt;" * 10, ERB::Util.html_escape("'&\"><" * 10))

    assert_equal("", ERB::Util.html_escape(nil))
    assert_equal("123", ERB::Util.html_escape(123))

    assert_equal(65536+5, ERB::Util.html_escape("x"*65536 + "&").size)
    assert_equal(65536+5, ERB::Util.html_escape("&" + "x"*65536).size)
  end

  def test_html_escape_string_subclass
    klass = Class.new(String) do
      def to_s
        "<to_s>"
      end
    end
    assert_equal("&lt;b&gt;", ERB::Util.html_escape(klass.new("<b>")))
  end

  def test_html_escape_to_s
    object = Object.new
    def object.to_s
      "object"
    end
    assert_equal("object", ERB::Util.html_escape(object))
  end

  def test_html_escape_extension
    assert_nil(ERB::Util.method(:html_escape).source_location)
  end if RUBY_ENGINE == 'ruby'

  def test_util_html_escape_in_ractor
    assert_ractor(<<~RUBY, require: 'erb')
      r = Ractor.new do
        ERB::Util.html_escape("<script>")
      end
      assert_equal("&lt;script&gt;", r.value)
    RUBY
  end

  def test_simd_coverage
    16.times do |i|
      str = "#{'.' * i}<#{'.' * (16-i-1)}#{'<' * 16}"
      esc = "#{'.' * i}&lt;#{'.'* (16-i-1)}#{'&lt;' * 16}"
      assert_equal esc, h(str)
    end

    assert_equal '&lt;' * 32, h('<' * 32)
  end

  def test_html_escape_simd_block_boundary
    # Ensure we only escape the characters that need to be escaped.
    (0...128).each do |pos|
      s = "a" * 128
      s[pos] = "<"
      expected = "a" * pos + "&lt;" + "a" * (128 - pos - 1)
      assert_equal(expected, ERB::Util.html_escape(s), "escape at position #{pos}")
    end
  end

  HTML_ESCAPE_ENTITIES = {"'" => "&#39;", '"' => "&quot;", "&" => "&amp;", "<" => "&lt;", ">" => "&gt;"}

  def test_html_escape_simd_multiple_matches_per_block
    chars = ["'", '"', '&', '<', '>']
    (0..15).each do |a|
      (0..15).each do |b|
        next if a == b
        s = "a" * 32
        s[a] = chars[a % chars.size]
        s[b] = chars[b % chars.size]
        expected = Array.new(32, "a")
        expected[a] = HTML_ESCAPE_ENTITIES[chars[a % chars.size]]
        expected[b] = HTML_ESCAPE_ENTITIES[chars[b % chars.size]]
        assert_equal(expected.join, ERB::Util.html_escape(s), "positions #{a}, #{b}")
      end
    end
  end

  def test_html_escape_simd_tail_lengths
    (1..128).each do |len|
      (0...len).each do |pos|
        s = "a" * len
        s[pos] = ">"
        expected = "a" * pos + "&gt;" + "a" * (len - pos - 1)
        assert_equal(expected, ERB::Util.html_escape(s), "len=#{len} pos=#{pos}")
      end
    end
  end

  def test_html_escape_simd_wide_block_boundary
    # Ensure a 64-byte-wide SIMD fast path correctly locates a match
    # at every byte position, including the last byte of the block
    # (which is special-cased in find_next_match_neon).
    (0...128).each do |pos|
      s = "a" * 128
      s[pos] = "<"
      expected = "a" * pos + "&lt;" + "a" * (128 - pos - 1)
      assert_equal(expected, ERB::Util.html_escape(s), "escape at position #{pos}")
    end
  end

  def test_html_escape_simd_wide_block_multiple_matches
    chars = ["'", '"', '&', '<', '>']
    boundary_positions = [0, 1, 15, 16, 17, 31, 32, 33, 47, 48, 49, 62, 63]
    boundary_positions.each do |a|
      boundary_positions.each do |b|
        next if a == b
        s = "a" * 64
        s[a] = chars[a % chars.size]
        s[b] = chars[b % chars.size]
        expected = Array.new(64, "a")
        expected[a] = HTML_ESCAPE_ENTITIES[chars[a % chars.size]]
        expected[b] = HTML_ESCAPE_ENTITIES[chars[b % chars.size]]
        assert_equal(expected.join, ERB::Util.html_escape(s), "positions #{a}, #{b}")
      end
    end
  end

  def test_html_escape_simd_wide_block_tail_lengths
    ([*56..72] + [*120..136]).each do |len|
      (0...len).each do |pos|
        s = "a" * len
        s[pos] = ">"
        expected = "a" * pos + "&gt;" + "a" * (len - pos - 1)
        assert_equal(expected, ERB::Util.html_escape(s), "len=#{len} pos=#{pos}")
      end
    end
  end

  private

  def h(...)
    ERB::Util.html_escape(...)
  end
end
