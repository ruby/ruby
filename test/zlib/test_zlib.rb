require 'test/unit/testsuite'
require 'test/unit/testcase'
require 'stringio'

begin
  require 'zlib'
rescue LoadError
end

if defined? Zlib
  class TestZlibGzipReader < Test::Unit::TestCase
    D0 = "\037\213\010\000S`\017A\000\003\003\000\000\000\000\000\000\000\000\000"
    def test_read0
      assert_equal("", Zlib::GzipReader.new(StringIO.new(D0)).read(0))
    end
  end

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
