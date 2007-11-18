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

    def test_ungetc
      s = ""
      w = Zlib::GzipWriter.new(StringIO.new(s))
      w << (1...1000).to_a.inspect
      w.close
      r = Zlib::GzipReader.new(StringIO.new(s))
      r.read(100)
      r.ungetc ?a
      assert_nothing_raised("[ruby-dev:24060]") {
        r.read(100)
        r.read
        r.close
      }
    end

    def test_ungetc_paragraph
      s = ""
      w = Zlib::GzipWriter.new(StringIO.new(s))
      w << "abc"
      w.close
      r = Zlib::GzipReader.new(StringIO.new(s))
      r.ungetc ?\n
      assert_equal("abc", r.gets(""))
      assert_nothing_raised("[ruby-dev:24065]") {
        r.read
        r.close
      }
    end
  end

  class TestZlibGzipWriter < Test::Unit::TestCase
    def test_invalid_new
      assert_raise(NoMethodError, "[ruby-dev:23228]") { Zlib::GzipWriter.new(nil).close }
      assert_raise(NoMethodError, "[ruby-dev:23344]") { Zlib::GzipWriter.new(true).close }
      assert_raise(NoMethodError, "[ruby-dev:23344]") { Zlib::GzipWriter.new(0).close }
      assert_raise(NoMethodError, "[ruby-dev:23344]") { Zlib::GzipWriter.new(:hoge).close }
    end
  end
end
