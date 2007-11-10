require 'test/unit'
require 'rubygems/gem_open_uri'

class TestOpenURI < Test::Unit::TestCase

  def test_open_uri_not_broken
    assert_nothing_raised do
      open __FILE__ do end
    end
  end

end

