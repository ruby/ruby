require 'test/unit'
require 'uri'

module URI


class TestCommon < Test::Unit::TestCase
  def setup
  end

  def teardown
  end

  def test_extract
    assert_equal(['http://example.com'],
		 URI.extract('http://example.com'))
    assert_equal(['http://example.com'],
		 URI.extract('(http://example.com)'))
    assert_equal(['http://example.com/foo)'],
		 URI.extract('(http://example.com/foo)'))
    assert_equal(['http://example.jphttp://example.jp'],
		 URI.extract('http://example.jphttp://example.jp'), "[ruby-list:36086]")
    assert_equal(['http://example.jphttp://example.jp'],
		 URI.extract('http://example.jphttp://example.jp', ['http']), "[ruby-list:36086]")
    assert_equal(['http://', 'mailto:'].sort,
		 URI.extract('ftp:// http:// mailto: https://', ['http', 'mailto']).sort)
    # reported by Doug Kearns <djkea2@mugca.its.monash.edu.au>
    assert_equal(['From:', 'mailto:xxx@xxx.xxx.xxx]'].sort,
		 URI.extract('From: XXX [mailto:xxx@xxx.xxx.xxx]').sort)
  end

  def test_regexp
    assert_instance_of Regexp, URI.regexp
    assert_instance_of Regexp, URI.regexp(['http'])
    assert_equal URI.regexp, URI.regexp
    assert_equal 'http://', 'x http:// x'.slice(URI.regexp)
    assert_equal 'http://', 'x http:// x'.slice(URI.regexp(['http']))
    assert_equal 'http://', 'x http:// x ftp://'.slice(URI.regexp(['http']))
    assert_equal nil, 'http://'.slice(URI.regexp([]))
    assert_equal nil, ''.slice(URI.regexp)
    assert_equal nil, 'xxxx'.slice(URI.regexp)
    assert_equal nil, ':'.slice(URI.regexp)
    assert_equal 'From:', 'From:'.slice(URI.regexp)
  end

  def test_kernel_uri
    expected = URI.parse("http://www.ruby-lang.org/")
    assert_equal(expected, URI("http://www.ruby-lang.org/"))
    assert_equal(expected, Kernel::URI("http://www.ruby-lang.org/"))
    assert_raise(NoMethodError) { Object.new.URI("http://www.ruby-lang.org/") }
  end

  def test_encode_www_form_component
    assert_equal("%00+%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F09%3A%3B%3C%3D%3E%3F%40" \
                 "AZ%5B%5C%5D%5E_%60az%7B%7C%7D%7E",
                 URI.encode_www_form_component("\x00 !\"\#$%&'()*+,-./09:;<=>?@AZ[\\]^_`az{|}~"))
    assert_equal("%95A", URI.encode_www_form_component(
                   "\x95\x41".force_encoding(Encoding::Shift_JIS)))
    assert_equal("%E3%81%82", URI.encode_www_form_component(
                   "\x30\x42".force_encoding(Encoding::UTF_16BE)))
    assert_equal("%1B%24B%24%22%1B%28B", URI.encode_www_form_component(
                   "\e$B$\"\e(B".force_encoding(Encoding::ISO_2022_JP)))
  end

  def test_decode_www_form_component
    assert_equal("  !\"\#$%&'()*+,-./09:;<=>?@AZ[\\]^_`az{|}~",
                 URI.decode_www_form_component(
                   "%20+%21%22%23%24%25%26%27%28%29*%2B%2C-.%2F09%3A%3B%3C%3D%3E%3F%40" \
                   "AZ%5B%5C%5D%5E_%60az%7B%7C%7D%7E"))
    assert_equal("\xA1\xA2".force_encoding(Encoding::EUC_JP),
                 URI.decode_www_form_component("%A1%A2", "EUC-JP"))
    assert_raise(ArgumentError){URI.decode_www_form_component("%")}
  end

  def test_encode_www_form
    assert_equal("a=1", URI.encode_www_form("a" => "1"))
    assert_equal("a=1", URI.encode_www_form(a: 1))
    assert_equal("a=1", URI.encode_www_form([["a", "1"]]))
    assert_equal("a=1", URI.encode_www_form([[:a, 1]]))
    expected = "a=1&%E3%81%82=%E6%BC%A2"
    assert_equal(expected, URI.encode_www_form("a" => "1", "\u3042" => "\u6F22"))
    assert_equal(expected, URI.encode_www_form(a: 1, :"\u3042" => "\u6F22"))
    assert_equal(expected, URI.encode_www_form([["a", "1"], ["\u3042", "\u6F22"]]))
    assert_equal(expected, URI.encode_www_form([[:a, 1], [:"\u3042", "\u6F22"]]))
  end

  def test_decode_www_form
    assert_equal([%w[a 1], %w[a 2]], URI.decode_www_form("a=1&a=2"))
    assert_equal([%w[a 1], ["\u3042", "\u6F22"]],
                 URI.decode_www_form("a=1;%E3%81%82=%E6%BC%A2"))
    assert_equal([%w[?a 1], %w[a 2]], URI.decode_www_form("?a=1&a=2"))
    assert_equal([], URI.decode_www_form(""))
    assert_raise(ArgumentError){URI.decode_www_form("%=1")}
    assert_raise(ArgumentError){URI.decode_www_form("a=%")}
    assert_raise(ArgumentError){URI.decode_www_form("a=1&%=2")}
    assert_raise(ArgumentError){URI.decode_www_form("a=1&b=%")}
    assert_raise(ArgumentError){URI.decode_www_form("a&b")}
    bug4098 = '[ruby-core:33464]'
    assert_raise(ArgumentError, bug4098){URI.decode_www_form("a=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&b")}
  end
end


end
