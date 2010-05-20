require 'test/unit/testsuite'
require 'test/unit/testcase'
require 'stringio'
require 'tempfile'

begin
  require 'zlib'
rescue LoadError
end

if defined? Zlib
  class TestZlibDeflate < Test::Unit::TestCase
    def test_initialize
      z = Zlib::Deflate.new
      s = z.deflate("foo", Zlib::FINISH)
      assert_equal("foo", Zlib::Inflate.inflate(s))

      z = Zlib::Deflate.new
      s = z.deflate("foo")
      s << z.deflate(nil, Zlib::FINISH)
      assert_equal("foo", Zlib::Inflate.inflate(s))

      assert_raise(Zlib::StreamError) { Zlib::Deflate.new(10000) }
    end

    def test_dup
      z1 = Zlib::Deflate.new
      s = z1.deflate("foo")
      z2 = z1.dup
      s1 = s + z1.deflate("bar", Zlib::FINISH)
      s2 = s + z2.deflate("baz", Zlib::FINISH)
      assert_equal("foobar", Zlib::Inflate.inflate(s1))
      assert_equal("foobaz", Zlib::Inflate.inflate(s2))
    end

    def test_deflate
      s = Zlib::Deflate.deflate("foo")
      assert_equal("foo", Zlib::Inflate.inflate(s))

      assert_raise(Zlib::StreamError) { Zlib::Deflate.deflate("foo", 10000) }
    end

    def test_addstr
      z = Zlib::Deflate.new
      z << "foo"
      s = z.deflate(nil, Zlib::FINISH)
      assert_equal("foo", Zlib::Inflate.inflate(s))
    end

    def test_flush
      z = Zlib::Deflate.new
      z << "foo"
      s = z.flush
      z << "bar"
      s << z.flush_next_in
      z << "baz"
      s << z.flush_next_out
      s << z.deflate("qux", Zlib::FINISH)
      assert_equal("foobarbazqux", Zlib::Inflate.inflate(s))
    end

    def test_avail
      z = Zlib::Deflate.new
      assert_equal(0, z.avail_in)
      assert_equal(0, z.avail_out)
      z << "foo"
      z.avail_out += 100
      z << "bar"
      s = z.finish
      assert_equal("foobar", Zlib::Inflate.inflate(s))
    end

    def test_total
      z = Zlib::Deflate.new
      1000.times { z << "foo" }
      s = z.finish
      assert_equal(3000, z.total_in)
      assert_operator(3000, :>, z.total_out)
      assert_equal("foo" * 1000, Zlib::Inflate.inflate(s))
    end

    def test_data_type
      z = Zlib::Deflate.new
      assert([Zlib::ASCII, Zlib::BINARY, Zlib::UNKNOWN].include?(z.data_type))
    end

    def test_adler
      z = Zlib::Deflate.new
      z << "foo"
      s = z.finish
      assert_equal(0x02820145, z.adler)
    end

    def test_finished_p
      z = Zlib::Deflate.new
      assert_equal(false, z.finished?)
      z << "foo"
      assert_equal(false, z.finished?)
      s = z.finish
      assert_equal(true, z.finished?)
      z.close
      assert_raise(Zlib::Error) { z.finished? }
    end

    def test_closed_p
      z = Zlib::Deflate.new
      assert_equal(false, z.closed?)
      z << "foo"
      assert_equal(false, z.closed?)
      s = z.finish
      assert_equal(false, z.closed?)
      z.close
      assert_equal(true, z.closed?)
    end

    def test_params
      z = Zlib::Deflate.new
      z << "foo"
      z.params(Zlib::DEFAULT_COMPRESSION, Zlib::DEFAULT_STRATEGY)
      z << "bar"
      s = z.finish
      assert_equal("foobar", Zlib::Inflate.inflate(s))

      data = ('a'..'z').to_a.join
      z = Zlib::Deflate.new(Zlib::NO_COMPRESSION, Zlib::MAX_WBITS,
                            Zlib::DEF_MEM_LEVEL, Zlib::DEFAULT_STRATEGY)
      z << data[0, 10]
      z.params(Zlib::BEST_COMPRESSION, Zlib::DEFAULT_STRATEGY)
      z << data[10 .. -1]
      assert_equal(data, Zlib::Inflate.inflate(z.finish))

      z = Zlib::Deflate.new
      s = z.deflate("foo", Zlib::FULL_FLUSH)
      z.avail_out = 0
      z.params(Zlib::NO_COMPRESSION, Zlib::FILTERED)
      s << z.deflate("bar", Zlib::FULL_FLUSH)
      z.avail_out = 0
      z.params(Zlib::BEST_COMPRESSION, Zlib::HUFFMAN_ONLY)
      s << z.deflate("baz", Zlib::FINISH)
      assert_equal("foobarbaz", Zlib::Inflate.inflate(s))

      z = Zlib::Deflate.new
      assert_raise(Zlib::StreamError) { z.params(10000, 10000) }
      z.close # without this, outputs `zlib(finalizer): the stream was freed prematurely.'
    end

    def test_set_dictionary
      z = Zlib::Deflate.new
      z.set_dictionary("foo")
      s = z.deflate("foo" * 100, Zlib::FINISH)
      z = Zlib::Inflate.new
      assert_raise(Zlib::NeedDict) { z.inflate(s) }
      z.set_dictionary("foo")
      assert_equal("foo" * 100, z.inflate(s)) # ???

      z = Zlib::Deflate.new
      z << "foo"
      assert_raise(Zlib::StreamError) { z.set_dictionary("foo") }
      z.close # without this, outputs `zlib(finalizer): the stream was freed prematurely.'
    end

    def test_reset
      z = Zlib::Deflate.new
      z << "foo"
      z.reset
      z << "bar"
      s = z.finish
      assert_equal("bar", Zlib::Inflate.inflate(s))
    end

    def test_close
      z = Zlib::Deflate.new
      z.close
      assert_raise(Zlib::Error) { z << "foo" }
      assert_raise(Zlib::Error) { z.reset }
    end

    COMPRESS_MSG = '0000000100100011010001010110011110001001101010111100110111101111'
    def test_deflate_no_flush
      d = Zlib::Deflate.new
      d.deflate(COMPRESS_MSG, Zlib::SYNC_FLUSH) # for header output
      assert(d.deflate(COMPRESS_MSG, Zlib::NO_FLUSH).empty?)
      assert(!d.finish.empty?)
      d.close
    end

    def test_deflate_sync_flush
      d = Zlib::Deflate.new
      assert_nothing_raised do
        d.deflate(COMPRESS_MSG, Zlib::SYNC_FLUSH)
      end
      assert(!d.finish.empty?)
      d.close
    end

    def test_deflate_full_flush
      d = Zlib::Deflate.new
      assert_nothing_raised do
        d.deflate(COMPRESS_MSG, Zlib::FULL_FLUSH)
      end
      assert(!d.finish.empty?)
      d.close
    end

    def test_deflate_flush_finish
      d = Zlib::Deflate.new
      d.deflate("init", Zlib::SYNC_FLUSH) # for flushing header
      assert(!d.deflate(COMPRESS_MSG, Zlib::FINISH).empty?)
      d.close
    end

    def test_deflate_raise_after_finish
      d = Zlib::Deflate.new
      d.deflate("init")
      d.finish
      assert_raise(Zlib::StreamError) do
        d.deflate('foo')
      end
      #
      d = Zlib::Deflate.new
      d.deflate("init", Zlib::FINISH)
      assert_raise(Zlib::StreamError) do
        d.deflate('foo')
      end
    end
  end

  class TestZlibInflate < Test::Unit::TestCase
    def test_initialize
      assert_raise(Zlib::StreamError) { Zlib::Inflate.new(-1) }

      s = Zlib::Deflate.deflate("foo")
      z = Zlib::Inflate.new
      z << s << nil
      assert_equal("foo", z.finish)
    end

    def test_inflate
      s = Zlib::Deflate.deflate("foo")
      z = Zlib::Inflate.new
      s = z.inflate(s)
      s << z.inflate(nil)
      assert_equal("foo", s)
      z.inflate("foo") # ???
      z << "foo" # ???
    end

    def test_sync
      z = Zlib::Deflate.new
      s = z.deflate("foo" * 1000, Zlib::FULL_FLUSH)
      z.avail_out = 0
      z.params(Zlib::NO_COMPRESSION, Zlib::FILTERED)
      s << z.deflate("bar" * 1000, Zlib::FULL_FLUSH)
      z.avail_out = 0
      z.params(Zlib::BEST_COMPRESSION, Zlib::HUFFMAN_ONLY)
      s << z.deflate("baz" * 1000, Zlib::FINISH)

      z = Zlib::Inflate.new
      assert_raise(Zlib::DataError) { z << "\0" * 100 }
      assert_equal(false, z.sync(""))
      assert_equal(false, z.sync_point?)

      z = Zlib::Inflate.new
      assert_raise(Zlib::DataError) { z << "\0" * 100 + s }
      assert_equal(true, z.sync(""))
      #assert_equal(true, z.sync_point?)

      z = Zlib::Inflate.new
      assert_equal(false, z.sync("\0" * 100))
      assert_equal(false, z.sync_point?)

      z = Zlib::Inflate.new
      assert_equal(true, z.sync("\0" * 100 + s))
      #assert_equal(true, z.sync_point?)
    end

    def test_set_dictionary
      z = Zlib::Inflate.new
      assert_raise(Zlib::StreamError) { z.set_dictionary("foo") }
      z.close
    end
  end

  class TestZlibGzipFile < Test::Unit::TestCase
    def test_to_io
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      assert_kind_of(IO, f.to_io)
    end

    def test_crc
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      f.read
      assert_equal(0x8c736521, f.crc)
    end

    def test_mtime
      tim = Time.now

      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) do |gz|
        gz.mtime = -1
        gz.mtime = tim
        gz.print("foo")
        gz.flush
        assert_raise(Zlib::GzipFile::Error) { gz.mtime = Time.now }
      end

      f = Zlib::GzipReader.open(t.path)
      assert_equal(tim.to_i, f.mtime.to_i)
    end

    def test_level
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal(Zlib::DEFAULT_COMPRESSION, f.level)
    end

    def test_os_code
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal(Zlib::OS_CODE, f.os_code)
    end

    def test_orig_name
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) do |gz|
        gz.orig_name = "foobarbazqux\0quux"
        gz.print("foo")
        gz.flush
        assert_raise(Zlib::GzipFile::Error) { gz.orig_name = "quux" }
      end

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foobarbazqux", f.orig_name)
    end

    def test_comment
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) do |gz|
        gz.comment = "foobarbazqux\0quux"
        gz.print("foo")
        gz.flush
        assert_raise(Zlib::GzipFile::Error) { gz.comment = "quux" }
      end

      f = Zlib::GzipReader.open(t.path)
      assert_equal("foobarbazqux", f.comment)
    end

    def test_lineno
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\nqux\n") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal([0, "foo\n"], [f.lineno, f.gets])
      assert_equal([1, "bar\n"], [f.lineno, f.gets])
      f.lineno = 1000
      assert_equal([1000, "baz\n"], [f.lineno, f.gets])
      assert_equal([1001, "qux\n"], [f.lineno, f.gets])
    end

    def test_closed_p
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      assert_equal(false, f.closed?)
      f.read
      assert_equal(false, f.closed?)
      f.close
      assert_equal(true, f.closed?)
    end

    def test_sync
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

      f = Zlib::GzipReader.open(t.path)
      f.sync = true
      assert_equal(true, f.sync)
      f.read
      f.sync = false
      assert_equal(false, f.sync)
      f.close
    end

    def test_pos
      t = Tempfile.new("test_zlib_gzip_file")
      t.close
      Zlib::GzipWriter.open(t.path) do |gz|
        gz.print("foo")
        gz.flush
        assert_equal(3, gz.tell)
      end
    end

    def test_path
      t = Tempfile.new("test_zlib_gzip_file")
      t.close

      gz = Zlib::GzipWriter.open(t.path)
      unless gz.respond_to?(:path)
        gz.close
        return
      end
      gz.print("foo")
      assert_equal(t.path, gz.path)
      gz.close
      assert_equal(t.path, gz.path)

      f = Zlib::GzipReader.open(t.path)
      assert_equal(t.path, f.path)
      f.close
      assert_equal(t.path, f.path)

      s = ""
      sio = StringIO.new(s)
      gz = Zlib::GzipWriter.new(sio)
      gz.print("foo")
      assert_raise(NoMethodError) { gz.path }
      gz.close

      sio = StringIO.new(s)
      f = Zlib::GzipReader.new(sio)
      assert_raise(NoMethodError) { f.path }
      f.close
    end
  end

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

    def test_native_exception_from_zlib_on_broken_header
      corrupt = StringIO.new
      corrupt.write('borkborkbork')
      begin
        Zlib::GzipReader.new(corrupt)
        flunk()
      rescue Zlib::GzipReader::Error
      end
    end

    def test_wrap
      content = StringIO.new "", "r+"

      Zlib::GzipWriter.wrap(content) do |io|
        io.write "hello\nworld\n"
      end

      content = StringIO.new content.string, "rb"

      gin = Zlib::GzipReader.new(content)
      assert_equal("hello\n", gin.gets)
      assert_equal("world\n", gin.gets)
      assert_nil gin.gets
      assert gin.eof?
      gin.close
    end

    def test_each_line_no_block
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) { |io| io.write "hello\nworld\n" }
      lines = []
      z = Zlib::GzipReader.open(t.path)
      z.each_line do |line|
        lines << line
      end
      z.close

      assert_equal(2, lines.size, lines.inspect)
      assert_equal("hello\n", lines.first)
      assert_equal("world\n", lines.last)
    end

    def test_each_line_block
      t = Tempfile.new("test_zlib_gzip_reader")
      t.close
      Zlib::GzipWriter.open(t.path) { |io| io.write "hello\nworld\n" }
      lines = []
      Zlib::GzipReader.open(t.path) do |z|
        z.each_line do |line|
          lines << line
        end
      end
      assert_equal(2, lines.size, lines.inspect)
    end
  end

  class TestZlibGzipWriter < Test::Unit::TestCase
    def test_invalid_new
      # [ruby-dev:23228]
      assert_raise(NoMethodError) { Zlib::GzipWriter.new(nil).close }
      # [ruby-dev:23344]
      assert_raise(NoMethodError) { Zlib::GzipWriter.new(true).close }
      assert_raise(NoMethodError) { Zlib::GzipWriter.new(0).close }
      assert_raise(NoMethodError) { Zlib::GzipWriter.new(:hoge).close }
    end

    def test_empty_line
      t = Tempfile.new("test_zlib_gzip_writer")
      t.close
      Zlib::GzipWriter.open(t.path) { |io| io.write "hello\nworld\n\ngoodbye\n" }
      lines = nil
      Zlib::GzipReader.open(t.path) do |z|
        lines = z.readlines
      end
      assert_equal(4, lines.size, lines.inspect)
    end
  end
end
