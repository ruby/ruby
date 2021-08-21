require_relative 'helper'
require 'uri'
require 'rubygems/uri_parser'

class TestUriParser < Gem::TestCase
  def test_parse_uri_none_string
    assert_equal :not_a_uri, Gem::UriParser.parse_uri(:not_a_uri)
  end

  def test_parse_uri_invalid_uri
    assert_equal "https://www.example.com:80index", Gem::UriParser.parse_uri("https://www.example.com:80index")
  end

  def test_parse_uri
    assert_equal URI::HTTPS, Gem::UriParser.parse_uri("https://www.example.com").class
  end
end
