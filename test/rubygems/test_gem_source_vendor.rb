require 'rubygems/test_case'
require 'rubygems/source'

class TestGemSourceVendor < Gem::TestCase

  def test_initialize
    source = Gem::Source::Vendor.new 'vendor/foo'

    assert_equal 'vendor/foo', source.uri
  end

end

