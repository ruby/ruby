require 'test/unit'
require 'cgi'
require 'stringio'


class CGIUtilTest < Test::Unit::TestCase


  def setup
    ENV['REQUEST_METHOD'] = 'GET'
    @str1="&<>\" \xE3\x82\x86\xE3\x82\x93\xE3\x82\x86\xE3\x82\x93"
    @str1.force_encoding("UTF-8") if RUBY_VERSION>="1.9"
  end

  def teardown
    %W[REQUEST_METHOD SCRIPT_NAME].each do |name|
      ENV.delete(name)
    end
  end


  def test_cgi_escape
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93', CGI::escape(@str1))
    assert_equal('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93'.ascii_only?, CGI::escape(@str1).ascii_only?) if RUBY_VERSION>="1.9"
  end

  def test_cgi_unescape
    assert_equal(@str1, CGI::unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93'))
    assert_equal(@str1.encoding, CGI::unescape('%26%3C%3E%22+%E3%82%86%E3%82%93%E3%82%86%E3%82%93').encoding) if RUBY_VERSION>="1.9"
  end

end
