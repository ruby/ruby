require 'test/unit'
require 'cgi'
require 'stringio'


class CGIUtilTest < Test::Unit::TestCase
  include CGI::Util

  def setup
    ENV['REQUEST_METHOD'] = 'GET'
    @str1="&<>\" \xE3\x82\x86\xE3\x82\x93\xE3\x82\x86\xE3\x82\x93"
    @str1.force_encoding("UTF-8") if defined?(::Encoding)
  end

  def teardown
    %W[REQUEST_METHOD SCRIPT_NAME].each do |name|
      ENV.delete(name)
    end
  end


  def test_cgi_escape
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93', CGI::escape(@str1))
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93'.ascii_only?, CGI::escape(@str1).ascii_only?) if defined?(::Encoding)
  end

  def test_cgi_escape_with_invalid_byte_sequence
    assert_nothing_raised(ArgumentError) do
      assert_equal('%C0%3C%3C', CGI::escape("\xC0\<\<".force_encoding("UTF-8")))
    end
  end

  def test_cgi_escape_preserve_encoding
    assert_equal(Encoding::US_ASCII, CGI::escape("\xC0\<\<".force_encoding("US-ASCII")).encoding)
    assert_equal(Encoding::ASCII_8BIT, CGI::escape("\xC0\<\<".force_encoding("ASCII-8BIT")).encoding)
    assert_equal(Encoding::UTF_8, CGI::escape("\xC0\<\<".force_encoding("UTF-8")).encoding)
  end

  def test_cgi_unescape
    assert_equal(@str1, CGI::unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93'))
    assert_equal(@str1.encoding, CGI::unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93').encoding) if defined?(::Encoding)
    assert_equal("\u{30E1 30E2 30EA 691C 7D22}", CGI.unescape("\u{30E1 30E2 30EA}%E6%A4%9C%E7%B4%A2"))
  end

  def test_cgi_unescape_preserve_encoding
    assert_equal(Encoding::US_ASCII, CGI::unescape("%C0%3C%3C".force_encoding("US-ASCII")).encoding)
    assert_equal(Encoding::ASCII_8BIT, CGI::unescape("%C0%3C%3C".force_encoding("ASCII-8BIT")).encoding)
    assert_equal(Encoding::UTF_8, CGI::unescape("%C0%3C%3C".force_encoding("UTF-8")).encoding)
  end

  def test_cgi_pretty
    assert_equal("<HTML>\n  <BODY>\n  </BODY>\n</HTML>\n",CGI::pretty("<HTML><BODY></BODY></HTML>"))
    assert_equal("<HTML>\n\t<BODY>\n\t</BODY>\n</HTML>\n",CGI::pretty("<HTML><BODY></BODY></HTML>","\t"))
  end

  def test_cgi_escapeHTML
    assert_equal(CGI::escapeHTML("'&\"><"),"&#39;&amp;&quot;&gt;&lt;")
  end

  def test_cgi_unescapeHTML
    assert_equal(CGI::unescapeHTML("&#39;&amp;&quot;&gt;&lt;"),"'&\"><")
  end

  def test_cgi_unescapeHTML_uppercasecharacter
    assert_equal(CGI::unescapeHTML("&#x3042;&#x3044;&#X3046;"),"\xE3\x81\x82\xE3\x81\x84\xE3\x81\x86")
  end

  def test_cgi_include_escape
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93', escape(@str1))
  end

  def test_cgi_include_escapeHTML
    assert_equal(escapeHTML("'&\"><"),"&#39;&amp;&quot;&gt;&lt;")
  end

  def test_cgi_include_h
    assert_equal(h("'&\"><"),"&#39;&amp;&quot;&gt;&lt;")
  end

  def test_cgi_include_unescape
    assert_equal(@str1, unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93'))
    assert_equal(@str1.encoding, unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93').encoding) if defined?(::Encoding)
    assert_equal("\u{30E1 30E2 30EA 691C 7D22}", unescape("\u{30E1 30E2 30EA}%E6%A4%9C%E7%B4%A2"))
  end

  def test_cgi_include_unescapeHTML
    assert_equal(unescapeHTML("&#39;&amp;&quot;&gt;&lt;"),"'&\"><")
  end

  def test_cgi_escapeElement
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escapeElement('<BR><A HREF="url"></A>', "A", "IMG"))
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escapeElement('<BR><A HREF="url"></A>', ["A", "IMG"]))
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escape_element('<BR><A HREF="url"></A>', "A", "IMG"))
    assert_equal("<BR>&lt;A HREF=&quot;url&quot;&gt;&lt;/A&gt;", escape_element('<BR><A HREF="url"></A>', ["A", "IMG"]))
  end


  def test_cgi_unescapeElement
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescapeElement(escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG"))
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescapeElement(escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"]))
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescape_element(escapeHTML('<BR><A HREF="url"></A>'), "A", "IMG"))
    assert_equal('&lt;BR&gt;<A HREF="url"></A>', unescape_element(escapeHTML('<BR><A HREF="url"></A>'), ["A", "IMG"]))
  end
end
