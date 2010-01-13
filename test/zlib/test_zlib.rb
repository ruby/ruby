require 'test/unit'
require 'stringio'
require 'tempfile'

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

    def test_ungetc # [ruby-dev:24060]
      s = ""
      w = Zlib::GzipWriter.new(StringIO.new(s))
      w << (1...1000).to_a.inspect
      w.close
      r = Zlib::GzipReader.new(StringIO.new(s))
      r.read(100)
      r.ungetc ?a
      assert_nothing_raised {
        r.read(100)
        r.read
        r.close
      }
    end

    def test_ungetc_paragraph # [ruby-dev:24065]
      s = ""
      w = Zlib::GzipWriter.new(StringIO.new(s))
      w << "abc"
      w.close
      r = Zlib::GzipReader.new(StringIO.new(s))
      r.ungetc ?\n
      assert_equal("abc", r.gets(""))
      assert_nothing_raised {
        r.read
        r.close
      }
    end

    def test_open
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      assert_raise(ArgumentError) { Zlib::GzipReader.open }

      assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foo", f.read)
      f.close
    end

    def test_rewind
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foo", f.read)
      f.rewind
      assert_equal("foo", f.read)
      f.close
    end

    def test_unused
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foo", f.read(3))
      f.unused
      assert_equal("bar", f.read)
      f.unused
      f.close
    end

    def test_read
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      str = "\u3042\u3044\u3046"
      Zlib::GzipWriter.open(t.path) {|gz| gz.print(str) }

      f = Zlib::GzipReader.open(t.path)
      assert_raise(ArgumentError) { f.read(-1) }
      assert_equal(str, f.read)
    end

    def test_readpartial
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

      f = Zlib::GzipReader.open(t.path)
      if f.respond_to?(:readpartial)
        assert("foo".start_with?(f.readpartial(3)))

        f = Zlib::GzipReader.open(t.path)
        s = ""
        f.readpartial(3, s)
        assert("foo".start_with?(s))

        assert_raise(ArgumentError) { f.readpartial(-1) }
      end
    end

    def test_getc
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

      f = Zlib::GzipReader.open(t.path)
      # .chr should not be needed in the future.
      # f.getc of 1.9 returns "f" instead of 102.
      "foobar".each_char {|c| assert_equal(c, f.getc.chr) }
      assert_nil(f.getc)
    end

    def test_getbyte
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

      f = Zlib::GzipReader.open(t.path)
      if f.respond_to?(:getbyte)
        "foobar".each_byte {|c| assert_equal(c, f.getbyte) }
        assert_nil(f.getbyte)
      end
    end

    def test_readchar
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

      f = Zlib::GzipReader.open(t.path)
      "foobar".each_byte {|c| assert_equal(c, f.readchar.ord) }
      assert_raise(EOFError) { f.readchar }
    end

    def test_each_byte
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

      f = Zlib::GzipReader.open(t.path)
      a = []
      f.each_byte {|c| a << c }
      assert_equal("foobar".each_byte.to_a, a)
    end

    def test_gets
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foo\n", f.gets)
      assert_equal("bar\n", f.gets)
      assert_equal("baz\n", f.gets)
      assert_nil(f.gets)
      f.close

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foo\nbar\nbaz\n", f.gets(nil))
      f.close
    end

    def test_gets
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foo\n", f.readline)
      assert_equal("bar\n", f.readline)
      assert_equal("baz\n", f.readline)
      assert_raise(EOFError) { f.readline }
      f.close
    end

    def test_each
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

      f = Zlib::GzipReader.open(t.path)
      a = ["foo\n", "bar\n", "baz\n"]
      f.each {|l| assert_equal(a.shift, l) }
      f.close
    end

    def test_readlines
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal(["foo\n", "bar\n", "baz\n"], f.readlines)
      f.close
    end

    def test_reader_wrap
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }
      f = open(t.path)
      assert_equal("foo", Zlib::GzipReader.wrap(f) {|gz| gz.read })
      assert_raise(IOError) { f.close }
    end
  end

  class TestZlibGzipWriter < Test::Unit::TestCase
    def test_invalid_new
      assert_raise(NoMethodError, "[ruby-dev:23228]") { Zlib::GzipWriter.new(nil).close }
      assert_raise(NoMethodError, "[ruby-dev:23344]") { Zlib::GzipWriter.new(true).close }
      assert_raise(NoMethodError, "[ruby-dev:23344]") { Zlib::GzipWriter.new(0).close }
      assert_raise(NoMethodError, "[ruby-dev:23344]") { Zlib::GzipWriter.new(:hoge).close }
    end

    def test_open
      assert_raise(ArgumentError) { Zlib::GzipWriter.open }

      t = Tempfile.new("test_zlib_gzip_writer")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }
      assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })

      f = Zlib::GzipWriter.open(t.path)
      f.print("bar")
      f.close
      assert_equal("bar", Zlib::GzipReader.open(t.path) {|gz| gz.read })

      assert_raise(Zlib::StreamError) { Zlib::GzipWriter.open(t.path, 10000) }
    end

    def test_write
      t = Tempfile.new("test_zlib_gzip_writer")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }
      assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })

      o = Object.new
      def o.to_s; "bar"; end
      Zlib::GzipWriter.open(t.path) {|gz| gz.print(o) }
      assert_equal("bar", Zlib::GzipReader.open(t.path) {|gz| gz.read })
    end

    def test_putc
      t = Tempfile.new("test_zlib_gzip_writer")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.putc(?x) }
      assert_equal("x", Zlib::GzipReader.open(t.path) {|gz| gz.read })

      # todo: multibyte char
    end

    def test_writer_wrap
      t = Tempfile.new("test_zlib_gzip_writer")
      Zlib::GzipWriter.wrap(t) {|gz| gz.print("foo") }
      t.close
      assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })
    end
  end

  class TestZlib < Test::Unit::TestCase
    def test_version
      assert_instance_of(String, Zlib.zlib_version)
      assert(Zlib.zlib_version.tainted?)
    end

    def test_adler32
      assert_equal(0x00000001, Zlib.adler32)
      assert_equal(0x02820145, Zlib.adler32("foo"))
      assert_equal(0x02820145, Zlib.adler32("o", Zlib.adler32("fo")))
      assert_equal(0x8a62c964, Zlib.adler32("abc\x01\x02\x03" * 10000))
    end

    def test_crc32
      assert_equal(0x00000000, Zlib.crc32)
      assert_equal(0x8c736521, Zlib.crc32("foo"))
      assert_equal(0x8c736521, Zlib.crc32("o", Zlib.crc32("fo")))
      assert_equal(0x07f0d68f, Zlib.crc32("abc\x01\x02\x03" * 10000))
    end

    def test_crc_table
      t = Zlib.crc_table
      assert_instance_of(Array, t)
      t.each {|x| assert_kind_of(Integer, x) }
    end
  end
end
