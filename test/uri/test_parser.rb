# frozen_string_literal: false
require 'test/unit'
require 'uri'

class URI::TestParser < Test::Unit::TestCase
  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_inspect
    assert_match(/URI::RFC2396_Parser/, URI::RFC2396_Parser.new.inspect)
    assert_match(/URI::RFC3986_Parser/, URI::Parser.new.inspect)
  end

  def test_compare
    url = 'http://a/b/c/d;p?q'
    u0 = URI.parse(url)
    u1 = URI.parse(url)
    p = URI::Parser.new
    u2 = p.parse(url)
    u3 = p.parse(url)

    assert(u0 == u1)
    assert(u0.eql?(u1))
    assert(!u0.equal?(u1))

    assert(u1 == u2)
    assert(!u1.eql?(u2))
    assert(!u1.equal?(u2))

    assert(u2 == u3)
    assert(u2.eql?(u3))
    assert(!u2.equal?(u3))
  end

  def test_parse
    escaped = URI::REGEXP::PATTERN::ESCAPED
    hex = URI::REGEXP::PATTERN::HEX
    p1 = URI::Parser.new(:ESCAPED => "(?:#{escaped}|%u[#{hex}]{4})")
    u1 = p1.parse('http://a/b/%uABCD')
    assert_equal(['http', nil, 'a', URI::HTTP.default_port, '/b/%uABCD', nil, nil],
		 uri_to_ary(u1))
    u1.path = '/%uDCBA'
    assert_equal(['http', nil, 'a', URI::HTTP.default_port, '/%uDCBA', nil, nil],
		 uri_to_ary(u1))
  end

  def test_parse_query_pct_encoded
    assert_equal('q=%32!$&-/?.09;=:@AZ_az~', URI.parse('https://www.example.com/search?q=%32!$&-/?.09;=:@AZ_az~').query)
    assert_raise(URI::InvalidURIError) { URI.parse('https://www.example.com/search?q=%XX') }
  end

  def test_parse_auth
    str = "http://al%40ice:p%40s%25sword@example.com/dir%2Fname/subdir?foo=bar%40example.com"
    uri = URI.parse(str)
    assert_equal "al%40ice", uri.user
    assert_equal "p%40s%25sword", uri.password
    assert_equal "al@ice", uri.decoded_user
    assert_equal "p@s%sword", uri.decoded_password
  end

  def test_raise_bad_uri_for_integer
    assert_raise(URI::InvalidURIError) do
      URI.parse(1)
    end
  end

  def test_unescape
    p1 = URI::Parser.new
    assert_equal("\xe3\x83\x90", p1.unescape("\xe3\x83\x90"))
    assert_equal("\xe3\x83\x90", p1.unescape('%e3%83%90'))
    assert_equal("\u3042", p1.unescape('%e3%81%82'.force_encoding(Encoding::US_ASCII)))
    assert_equal("\xe3\x83\x90\xe3\x83\x90", p1.unescape("\xe3\x83\x90%e3%83%90"))
  end

  def test_split
    assert_equal(["http", nil, "example.com", nil, nil, "", nil, nil, nil], URI.split("http://example.com"))
    assert_equal(["http", nil, "[0::0]", nil, nil, "", nil, nil, nil], URI.split("http://[0::0]"))
    assert_equal([nil, nil, "example.com", nil, nil, "", nil, nil, nil], URI.split("//example.com"))
    assert_equal([nil, nil, "[0::0]", nil, nil, "", nil, nil, nil], URI.split("//[0::0]"))

    assert_equal(["a", nil, nil, nil, nil, "", nil, nil, nil], URI.split("a:"))
    assert_raise(URI::InvalidURIError) do
      URI.parse("::")
    end
    assert_raise(URI::InvalidURIError) do
      URI.parse("foo@example:foo")
    end
  end

  def test_rfc2822_parse_relative_uri
    pre = ->(length) {
      " " * length + "\0"
    }
    parser = URI::RFC2396_Parser.new
    assert_linear_performance((1..5).map {|i| 10**i}, pre: pre) do |uri|
      assert_raise(URI::InvalidURIError) do
        parser.split(uri)
      end
    end
  end

  def test_rfc3986_port_check
    pre = ->(length) {"\t" * length + "a"}
    uri = URI.parse("http://my.example.com")
    assert_linear_performance((1..5).map {|i| 10**i}, pre: pre) do |port|
      assert_raise(URI::InvalidComponentError) do
        uri.port = port
      end
    end
  end
end
