# frozen_string_literal: true
require 'test/unit'
require 'cgi'
require 'stringio'
require_relative 'update_env'


class CGIUtilTest < Test::Unit::TestCase
  include CGI::Escape
  include UpdateEnv

  def setup
    @environ = {}
    update_env(
      'REQUEST_METHOD' => 'GET',
      'SCRIPT_NAME' => nil,
    )
    @str1="&<>\" \xE3\x82\x86\xE3\x82\x93\xE3\x82\x86\xE3\x82\x93".dup
    @str1.force_encoding("UTF-8") if defined?(::Encoding)
  end

  def teardown
    ENV.update(@environ)
  end

  def test_cgi_escape
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93', CGI.escape(@str1))
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93'.ascii_only?, CGI.escape(@str1).ascii_only?) if defined?(::Encoding)
  end

  def test_cgi_escape_with_unreserved_characters
    assert_equal("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
                 CGI.escape("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"),
                 "should not escape any unreserved characters, as per RFC3986 Section 2.3")
  end

  def test_cgi_escape_with_invalid_byte_sequence
    assert_equal('%C0%3C%3C', CGI.escape("\xC0\<\<".dup.force_encoding("UTF-8")))
  end

  def test_cgi_escape_preserve_encoding
    assert_equal(Encoding::US_ASCII, CGI.escape("\xC0\<\<".dup.force_encoding("US-ASCII")).encoding)
    assert_equal(Encoding::ASCII_8BIT, CGI.escape("\xC0\<\<".dup.force_encoding("ASCII-8BIT")).encoding)
    assert_equal(Encoding::UTF_8, CGI.escape("\xC0\<\<".dup.force_encoding("UTF-8")).encoding)
  end

  def test_cgi_unescape
    str = CGI.unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93')
    assert_equal(@str1, str)
    return unless defined?(::Encoding)

    assert_equal(@str1.encoding, str.encoding)
    assert_equal("\u{30E1 30E2 30EA 691C 7D22}", CGI.unescape("\u{30E1 30E2 30EA}%E6%A4%9C%E7%B4%A2"))
  end

  def test_cgi_unescape_preserve_encoding
    assert_equal(Encoding::US_ASCII, CGI.unescape("%C0%3C%3C".dup.force_encoding("US-ASCII")).encoding)
    assert_equal(Encoding::ASCII_8BIT, CGI.unescape("%C0%3C%3C".dup.force_encoding("ASCII-8BIT")).encoding)
    assert_equal(Encoding::UTF_8, CGI.unescape("%C0%3C%3C".dup.force_encoding("UTF-8")).encoding)
  end

  def test_cgi_unescape_accept_charset
    return unless defined?(::Encoding)

    assert_raise(TypeError) {CGI.unescape('', nil)}
    assert_separately(%w[-rcgi/escape], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      assert_equal("", CGI.unescape(''))
    end;
  end

  def test_cgi_escapeURIComponent
    assert_equal('%26%3C%3E%22%20%E3%82%86%E3%82%93%E3%82%86%E3%82%93', CGI.escapeURIComponent(@str1))
    assert_equal('%26%3C%3E%22%20%E3%82%86%E3%82%93%E3%82%86%E3%82%93'.ascii_only?, CGI.escapeURIComponent(@str1).ascii_only?) if defined?(::Encoding)
  end

  def test_cgi_escape_uri_component
    assert_equal('%26%3C%3E%22%20%E3%82%86%E3%82%93%E3%82%86%E3%82%93', CGI.escape_uri_component(@str1))
  end

  def test_cgi_escapeURIComponent_with_unreserved_characters
    assert_equal("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~",
                 CGI.escapeURIComponent("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"),
                 "should not encode any unreserved characters, as per RFC3986 Section 2.3")
  end

  def test_cgi_escapeURIComponent_with_invalid_byte_sequence
    assert_equal('%C0%3C%3C', CGI.escapeURIComponent("\xC0\<\<".dup.force_encoding("UTF-8")))
  end

  def test_cgi_escapeURIComponent_preserve_encoding
    assert_equal(Encoding::US_ASCII, CGI.escapeURIComponent("\xC0\<\<".dup.force_encoding("US-ASCII")).encoding)
    assert_equal(Encoding::ASCII_8BIT, CGI.escapeURIComponent("\xC0\<\<".dup.force_encoding("ASCII-8BIT")).encoding)
    assert_equal(Encoding::UTF_8, CGI.escapeURIComponent("\xC0\<\<".dup.force_encoding("UTF-8")).encoding)
  end

  def test_cgi_unescapeURIComponent
    str = CGI.unescapeURIComponent('%26%3C%3E%22%20%E3%82%86%E3%82%93%E3%82%86%E3%82%93')
    assert_equal(@str1, str)
    return unless defined?(::Encoding)

    assert_equal("foo+bar", CGI.unescapeURIComponent("foo+bar"))

    assert_equal(@str1.encoding, str.encoding)
    assert_equal("\u{30E1 30E2 30EA 691C 7D22}", CGI.unescapeURIComponent("\u{30E1 30E2 30EA}%E6%A4%9C%E7%B4%A2"))
  end

  def test_cgi_unescape_uri_component
    str = CGI.unescape_uri_component('%26%3C%3E%22%20%E3%82%86%E3%82%93%E3%82%86%E3%82%93')
    assert_equal(@str1, str)
  end

  def test_cgi_unescapeURIComponent_preserve_encoding
    assert_equal(Encoding::US_ASCII, CGI.unescapeURIComponent("%C0%3C%3C".dup.force_encoding("US-ASCII")).encoding)
    assert_equal(Encoding::ASCII_8BIT, CGI.unescapeURIComponent("%C0%3C%3C".dup.force_encoding("ASCII-8BIT")).encoding)
    assert_equal(Encoding::UTF_8, CGI.unescapeURIComponent("%C0%3C%3C".dup.force_encoding("UTF-8")).encoding)
  end

  def test_cgi_unescapeURIComponent_accept_charset
    return unless defined?(::Encoding)

    assert_raise(TypeError) {CGI.unescapeURIComponent('', nil)}
    assert_separately(%w[-rcgi/escape], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      assert_equal("", CGI.unescapeURIComponent(''))
    end;
  end

  def test_cgi_pretty
    assert_equal("<HTML>\n  <BODY>\n  </BODY>\n</HTML>\n",CGI.pretty("<HTML><BODY></BODY></HTML>"))
    assert_equal("<HTML>\n\t<BODY>\n\t</BODY>\n</HTML>\n",CGI.pretty("<HTML><BODY></BODY></HTML>","\t"))
  end

  def test_cgi_escapeHTML
    assert_equal("&#39;&amp;&quot;&gt;&lt;", CGI.escapeHTML("'&\"><"))
  end

  def test_cgi_escape_html_duplicated
    orig = "Ruby".dup.force_encoding("US-ASCII")
    str = CGI.escapeHTML(orig)
    assert_equal(orig, str)
    assert_not_same(orig, str)
  end

  def assert_cgi_escape_html_preserve_encoding(str, encoding)
    assert_equal(encoding, CGI.escapeHTML(str.dup.force_encoding(encoding)).encoding)
  end

  def test_cgi_escape_html_preserve_encoding
    Encoding.list do |enc|
      assert_cgi_escape_html_preserve_encoding("'&\"><", enc)
      assert_cgi_escape_html_preserve_encoding("Ruby", enc)
    end
  end

  def test_cgi_escape_html_dont_freeze
    assert_not_predicate CGI.escapeHTML("'&\"><".dup),    :frozen?
    assert_not_predicate CGI.escapeHTML("'&\"><".freeze), :frozen?
    assert_not_predicate CGI.escapeHTML("Ruby".dup),      :frozen?
    assert_not_predicate CGI.escapeHTML("Ruby".freeze),   :frozen?
  end

  def test_cgi_escape_html_large
    return if RUBY_ENGINE == 'jruby'
    ulong_max, size_max = RbConfig::LIMITS.values_at("ULONG_MAX", "SIZE_MAX")
    return unless ulong_max < size_max # Platforms not concerned

    size = (ulong_max / 6 + 1)
    begin
      str = '"' * size
      escaped = CGI.escapeHTML(str)
    rescue NoMemoryError
      omit "Not enough memory"
    rescue => e
    end
    assert_raise_with_message(ArgumentError, /overflow/, ->{"length = #{escaped.length}"}) do
      raise e if e
    end
  end

  def test_cgi_unescapeHTML
    assert_equal("'&\"><", CGI.unescapeHTML("&#39;&amp;&quot;&gt;&lt;"))
  end

  def test_cgi_unescapeHTML_invalid
    assert_equal('&<&amp>&quot&abcdefghijklmn', CGI.unescapeHTML('&&lt;&amp&gt;&quot&abcdefghijklmn'))
  end

  module UnescapeHTMLTests
    def test_cgi_unescapeHTML_following_known_first_letter
      assert_equal('&a>&q>&l>&g>', CGI.unescapeHTML('&a&gt;&q&gt;&l&gt;&g&gt;'))
    end

    def test_cgi_unescapeHTML_following_number_sign
      assert_equal('&#>&#x>', CGI.unescapeHTML('&#&gt;&#x&gt;'))
    end

    def test_cgi_unescapeHTML_following_invalid_numeric
      assert_equal('&#1114112>&#x110000>', CGI.unescapeHTML('&#1114112&gt;&#x110000&gt;'))
    end
  end

  include UnescapeHTMLTests

  Encoding.list.each do |enc|
    begin
      escaped = "&#39;&amp;&quot;&gt;&lt;".encode(enc)
      unescaped = "'&\"><".encode(enc)
    rescue Encoding::ConverterNotFoundError
      next
    else
      define_method("test_cgi_escapeHTML:#{enc.name}") do
        assert_equal(escaped, CGI.escapeHTML(unescaped))
      end
      define_method("test_cgi_unescapeHTML:#{enc.name}") do
        assert_equal(unescaped, CGI.unescapeHTML(escaped))
      end
    end
  end

  Encoding.list.each do |enc|
    next unless enc.ascii_compatible?
    begin
      escaped = "%25+%2B"
      unescaped = "% +".encode(enc)
    rescue Encoding::ConverterNotFoundError
      next
    else
      define_method("test_cgi_escape:#{enc.name}") do
        assert_equal(escaped, CGI.escape(unescaped))
      end
      define_method("test_cgi_unescape:#{enc.name}") do
        assert_equal(unescaped, CGI.unescape(escaped, enc))
      end
    end
  end

  def test_cgi_unescapeHTML_uppercasecharacter
    assert_equal("\xE3\x81\x82\xE3\x81\x84\xE3\x81\x86", CGI.unescapeHTML("&#x3042;&#x3044;&#X3046;"))
  end

  def test_cgi_include_escape
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93', escape(@str1))
  end

  def test_cgi_include_escapeHTML
    assert_equal("&#39;&amp;&quot;&gt;&lt;", escapeHTML("'&\"><"))
  end

  def test_cgi_include_h
    assert_equal("&#39;&amp;&quot;&gt;&lt;", h("'&\"><"))
  end

  def test_cgi_include_unescape
    str = unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93')
    assert_equal(@str1, str)
    return unless defined?(::Encoding)

    assert_equal(@str1.encoding, str.encoding)
    assert_equal("\u{30E1 30E2 30EA 691C 7D22}", unescape("\u{30E1 30E2 30EA}%E6%A4%9C%E7%B4%A2"))
  end

  def test_cgi_include_unescapeHTML
    assert_equal("'&\"><", unescapeHTML("&#39;&amp;&quot;&gt;&lt;"))
  end

  def test_cgi_escapeElement
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escapeElement('<BR><A HREF="url"></A>', "A", "IMG"))
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escapeElement('<BR><A HREF="url"></A>', ["A", "IMG"]))
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escape_element('<BR><A HREF="url"></A>', "A", "IMG"))
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escape_element('<BR><A HREF="url"></A>', ["A", "IMG"]))

    assert_equal("&lt;A &lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escapeElement('<A <A HREF="url"></A>', "A", "IMG"))
    assert_equal("&lt;A &lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escapeElement('<A <A HREF="url"></A>', ["A", "IMG"]))
    assert_equal("&lt;A &lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escape_element('<A <A HREF="url"></A>', "A", "IMG"))
    assert_equal("&lt;A &lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escape_element('<A <A HREF="url"></A>', ["A", "IMG"]))

    assert_equal("&lt;A &lt;A ", escapeElement('<A <A ', "A", "IMG"))
    assert_equal("&lt;A &lt;A ", escapeElement('<A <A ', ["A", "IMG"]))
  end


  def test_cgi_unescapeElement
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescapeElement(escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG"))
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescapeElement(escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"]))
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescape_element(escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG"))
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescape_element(escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"]))

    assert_equal('<A <A HREF="url"></A>', unescapeElement(escapeHTML('<A <A HREF="url"></A>'), "A", "IMG"))
    assert_equal('<A <A HREF="url"></A>', unescapeElement(escapeHTML('<A <A HREF="url"></A>'), ["A", "IMG"]))
    assert_equal('<A <A HREF="url"></A>', unescape_element(escapeHTML('<A <A HREF="url"></A>'), "A", "IMG"))
    assert_equal('<A <A HREF="url"></A>', unescape_element(escapeHTML('<A <A HREF="url"></A>'), ["A", "IMG"]))

    assert_equal('<A <A ', unescapeElement(escapeHTML('<A <A '), "A", "IMG"))
    assert_equal('<A <A ', unescapeElement(escapeHTML('<A <A '), ["A", "IMG"]))
    assert_equal('<A <A ', unescape_element(escapeHTML('<A <A '), "A", "IMG"))
    assert_equal('<A <A ', unescape_element(escapeHTML('<A <A '), ["A", "IMG"]))
  end
end

class CGIUtilPureRubyTest < Test::Unit::TestCase
  def setup
    CGI::EscapeExt.module_eval do
      alias _escapeHTML escapeHTML
      remove_method :escapeHTML
      alias _unescapeHTML unescapeHTML
      remove_method :unescapeHTML
    end if defined?(CGI::EscapeExt)
  end

  def teardown
    CGI::EscapeExt.module_eval do
      alias escapeHTML _escapeHTML
      remove_method :_escapeHTML
      alias unescapeHTML _unescapeHTML
      remove_method :_unescapeHTML
    end if defined?(CGI::EscapeExt)
  end

  include CGIUtilTest::UnescapeHTMLTests

  def test_cgi_escapeHTML_with_invalid_byte_sequence
    assert_equal("&lt;\xA4??&gt;", CGI.escapeHTML(%[<\xA4??>]))
  end

  def test_cgi_unescapeHTML_with_invalid_byte_sequence
    input = "\xFF&"
    assert_equal(input, CGI.unescapeHTML(input))
  end
end
