require 'test/unit/testsuite'
require 'test/unit/testcase'

require 'zlib'

class TestZlibGzipWriter < Test::Unit::TestCase
  def test_new_nil # [ruby-dev:23228]
    assert_raises(NoMethodError) { Zlib::GzipWriter.new(nil).close }
  end
end
