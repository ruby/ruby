require 'test/unit/testsuite'
require 'test/unit/testcase'

require 'zlib'

class TestZlibGzipWriter < Test::Unit::TestCase
  def test_new_nil # [ruby-dev:23228]
    old = $VERBOSE
    $VERBOSE = nil
    begin
      assert_raises(NoMethodError) { Zlib::GzipWriter.new(nil).close }
    ensure
      $VERBOSE = old
    end
  end
end
