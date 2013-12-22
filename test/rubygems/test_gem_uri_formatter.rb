require 'rubygems/test_case'
require 'rubygems/uri_formatter'

class TestGemUriFormatter < Gem::TestCase

  def test_normalize_uri
    assert_equal 'FILE://example/',
      Gem::UriFormatter.new('FILE://example/').normalize
    assert_equal 'FTP://example/',
      Gem::UriFormatter.new('FTP://example/').normalize
    assert_equal 'HTTP://example/',
      Gem::UriFormatter.new('HTTP://example/').normalize
    assert_equal 'HTTPS://example/',
      Gem::UriFormatter.new('HTTPS://example/').normalize
    assert_equal 'http://example/',
      Gem::UriFormatter.new('example/').normalize
  end

  def test_escape
    assert_equal 'a%40b%5Cc', Gem::UriFormatter.new('a@b\c').escape
  end

  def test_unescape
    assert_equal 'a@b\c', Gem::UriFormatter.new('a%40b%5Cc').unescape
  end

end

