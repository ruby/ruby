require 'test/unit/testsuite'
require 'test/unit/testcase'

begin
  require 'zlib'
rescue LoadError
end

if defined? Zlib
  class TestZlibGzipWriter < Test::Unit::TestCase
    def test_invalid_new
      # [ruby-dev:23228]
      assert_raises(NoMethodError) { Zlib::GzipWriter.new(nil).close }
      # [ruby-dev:23344]
      assert_raises(NoMethodError) { Zlib::GzipWriter.new(true).close }
      assert_raises(NoMethodError) { Zlib::GzipWriter.new(0).close }
      assert_raises(NoMethodError) { Zlib::GzipWriter.new(:hoge).close }
    end
  end
end
