# coding: us-ascii
# frozen_string_literal: true
require 'test/unit'
require 'stringio'
require 'tempfile'
require 'tmpdir'
require 'securerandom'

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

    def test_deflate_chunked
      original = ''.dup
      chunks = []
      r = Random.new 0

      z = Zlib::Deflate.new

      2.times do
        input = r.bytes(20000)
        original << input
        z.deflate(input) do |chunk|
          chunks << chunk
        end
      end

      assert_equal [16384, 16384],
                   chunks.map { |chunk| chunk.length }

      final = z.finish

      assert_equal 7253, final.length

      chunks << final
      all = chunks.join

      inflated = Zlib.inflate all

      assert_equal original, inflated
    end

    def test_deflate_chunked_break
      chunks = []
      r = Random.new 0

      z = Zlib::Deflate.new

      input = r.bytes(20000)
      z.deflate(input) do |chunk|
        chunks << chunk
        break
      end

      assert_equal [16384], chunks.map { |chunk| chunk.length }

      final = z.finish

      assert_equal 3632, final.length

      all = chunks.join
      all << final

      original = Zlib.inflate all

      assert_equal input, original
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

    def test_expand_buffer;
      z = Zlib::Deflate.new
      src = "baz" * 1000
      z.avail_out = 1
      GC.stress = true
      s = z.deflate(src, Zlib::FINISH)
      GC.stress = false
      assert_equal(src, Zlib::Inflate.inflate(s))
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
      z.finish
      assert_equal(0x02820145, z.adler)
    end

    def test_finished_p
      z = Zlib::Deflate.new
      assert_equal(false, z.finished?)
      z << "foo"
      assert_equal(false, z.finished?)
      z.finish
      assert_equal(true, z.finished?)
      z.close
      assert_raise(Zlib::Error) { z.finished? }
    end

    def test_closed_p
      z = Zlib::Deflate.new
      assert_equal(false, z.closed?)
      z << "foo"
      assert_equal(false, z.closed?)
      z.finish
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
      EnvUtil.suppress_warning {z.params(Zlib::NO_COMPRESSION, Zlib::FILTERED)}
      s << z.deflate("bar", Zlib::FULL_FLUSH)
      z.avail_out = 0
      EnvUtil.suppress_warning {z.params(Zlib::BEST_COMPRESSION, Zlib::HUFFMAN_ONLY)}
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
      EnvUtil.suppress_warning do
        z.close # without this, outputs `zlib(finalizer): the stream was freed prematurely.'
      end
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
  end

  class TestZlibInflate < Test::Unit::TestCase
    def test_class_inflate_dictionary
      assert_raise(Zlib::NeedDict) do
        Zlib::Inflate.inflate([0x08,0x3C,0x0,0x0,0x0,0x0].pack("c*"))
      end
    end

    def test_initialize
      assert_raise(Zlib::StreamError) { Zlib::Inflate.new(-1) }

      s = Zlib::Deflate.deflate("foo")
      z = Zlib::Inflate.new
      z << s << nil
      assert_equal("foo", z.finish)
    end

    def test_add_dictionary
      dictionary = "foo"

      deflate = Zlib::Deflate.new
      deflate.set_dictionary dictionary
      compressed = deflate.deflate "foofoofoo", Zlib::FINISH
      deflate.close

      out = nil
      inflate = Zlib::Inflate.new
      inflate.add_dictionary "foo"

      out = inflate.inflate compressed

      assert_equal "foofoofoo", out
    end

    def test_finish_chunked
      # zeros = Zlib::Deflate.deflate("0" * 100_000)
      zeros = "x\234\355\3011\001\000\000\000\302\240J\353\237\316\032\036@" \
              "\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\257\006\351\247BH"

      chunks = []

      z = Zlib::Inflate.new

      z.inflate(zeros) do |chunk|
        chunks << chunk
        break
      end

      z.finish do |chunk|
        chunks << chunk
      end

      assert_equal [16384, 16384, 16384, 16384, 16384, 16384, 1696],
                   chunks.map { |chunk| chunk.size }

      assert chunks.all? { |chunk|
        chunk =~ /\A0+\z/
      }
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

    def test_inflate_partial_input
      deflated = Zlib::Deflate.deflate "\0"

      z = Zlib::Inflate.new

      inflated = "".dup

      deflated.each_char do |byte|
        inflated << z.inflate(byte)
      end

      inflated << z.finish

      assert_equal "\0", inflated
    end

    def test_inflate_chunked
      # s = Zlib::Deflate.deflate("0" * 100_000)
      zeros = "x\234\355\3011\001\000\000\000\302\240J\353\237\316\032\036@" \
              "\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\257\006\351\247BH"

      chunks = []

      z = Zlib::Inflate.new

      z.inflate(zeros) do |chunk|
        chunks << chunk
      end

      assert_equal [16384, 16384, 16384, 16384, 16384, 16384, 1696],
                   chunks.map { |chunk| chunk.size }

      assert chunks.all? { |chunk|
        chunk =~ /\A0+\z/
      }
    end

    def test_inflate_buffer
      s = Zlib::Deflate.deflate("foo")
      z = Zlib::Inflate.new
      buf = String.new
      s = z.inflate(s, buffer: buf)
      assert_same(buf, s)
      buf = String.new
      s << z.inflate(nil, buffer: buf)
      assert_equal("foo", s)
      z.inflate("foo", buffer: buf) # ???
      z << "foo" # ???
    end

    def test_inflate_buffer_partial_input
      deflated = Zlib::Deflate.deflate "\0"

      z = Zlib::Inflate.new

      inflated = "".dup

      buf = String.new
      deflated.each_char do |byte|
        inflated << z.inflate(byte, buffer: buf)
      end

      inflated << z.finish

      assert_equal "\0", inflated
    end

    def test_inflate_buffer_chunked
      # s = Zlib::Deflate.deflate("0" * 100_000)
      zeros = "x\234\355\3011\001\000\000\000\302\240J\353\237\316\032\036@" \
              "\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\257\006\351\247BH"

      chunks = []

      z = Zlib::Inflate.new

      buf = String.new
      z.inflate(zeros, buffer: buf) do |chunk|
        assert_same(buf, chunk)
        chunks << chunk.dup
      end

      assert_equal [16384, 16384, 16384, 16384, 16384, 16384, 1696],
                   chunks.map { |chunk| chunk.size }

      assert chunks.all? { |chunk|
        chunk =~ /\A0+\z/
      }
    end

    def test_inflate_chunked_break
      # zeros = Zlib::Deflate.deflate("0" * 100_000)
      zeros = "x\234\355\3011\001\000\000\000\302\240J\353\237\316\032\036@" \
              "\001\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\000\000\000\000\000\000\000\000" \
              "\000\000\000\000\000\000\000\257\006\351\247BH"

      chunks = []

      z = Zlib::Inflate.new

      z.inflate(zeros) do |chunk|
        chunks << chunk
        break
      end

      out = z.inflate nil

      assert_equal 100_000 - chunks.first.length, out.length
    end

    def test_inflate_dictionary
      dictionary = "foo"

      deflate = Zlib::Deflate.new
      deflate.set_dictionary dictionary
      compressed = deflate.deflate "foofoofoo", Zlib::FINISH
      deflate.close

      out = nil
      inflate = Zlib::Inflate.new

      begin
        out = inflate.inflate compressed

        flunk "Zlib::NeedDict was not raised"
      rescue Zlib::NeedDict
        inflate.set_dictionary dictionary
        out = inflate.inflate ""
      end

      assert_equal "foofoofoo", out
    end

    def test_sync
      z = Zlib::Deflate.new
      s = z.deflate("foo" * 1000, Zlib::FULL_FLUSH)
      z.avail_out = 0
      EnvUtil.suppress_warning {z.params(Zlib::NO_COMPRESSION, Zlib::FILTERED)}
      s << z.deflate("bar" * 1000, Zlib::FULL_FLUSH)
      z.avail_out = 0
      EnvUtil.suppress_warning {z.params(Zlib::BEST_COMPRESSION, Zlib::HUFFMAN_ONLY)}
      s << z.deflate("baz" * 1000, Zlib::FINISH)

      z = Zlib::Inflate.new
      assert_raise(Zlib::DataError) { z << "\0" * 100 }
      assert_equal(false, z.sync(""))
      assert_equal(false, z.sync_point?)

      z = Zlib::Inflate.new
      assert_raise(Zlib::DataError) { z << "\0" * 100 + s }
      assert_equal(true, z.sync(""))

      z = Zlib::Inflate.new
      assert_equal(false, z.sync("\0" * 100))
      assert_equal(false, z.sync_point?)

      z = Zlib::Inflate.new
      assert_equal(true, z.sync("\0" * 100 + s))
    end

    def test_set_dictionary
      z = Zlib::Inflate.new
      assert_raise(Zlib::StreamError) { z.set_dictionary("foo") }
      z.close
    end

    def test_multithread_deflate
      zd = Zlib::Deflate.new

      s = "x" * 10000
      (0...10).map do |x|
        Thread.new do
          1000.times { zd.deflate(s) }
        end
      end.each do |th|
        th.join
      end
    ensure
      zd&.finish
      zd&.close
    end

    def test_multithread_inflate
      zi = Zlib::Inflate.new

      s = Zlib.deflate("x" * 10000)
      (0...10).map do |x|
        Thread.new do
          1000.times { zi.inflate(s) }
        end
      end.each do |th|
        th.join
      end
    ensure
      zi&.finish
      zi&.close
    end

    def test_recursive_deflate
      original_gc_stress = GC.stress
      GC.stress = true
      zd = Zlib::Deflate.new

      s = SecureRandom.random_bytes(1024**2)
      assert_raise(Zlib::InProgressError) do
        zd.deflate(s) do
          zd.deflate(s)
        end
      end
    ensure
      GC.stress = original_gc_stress
      zd&.finish
      zd&.close
    end

    def test_recursive_inflate
      original_gc_stress = GC.stress
      GC.stress = true
      zi = Zlib::Inflate.new

      s = Zlib.deflate(SecureRandom.random_bytes(1024**2))

      assert_raise(Zlib::InProgressError) do
        zi.inflate(s) do
          zi.inflate(s)
        end
      end
    ensure
      GC.stress = original_gc_stress
      zi&.close
    end
  end

  class TestZlibGzipFile < Test::Unit::TestCase
    def test_gzip_reader_zcat
      Tempfile.create("test_zlib_gzip_file_to_io") {|t|
        t.binmode
        gz = Zlib::GzipWriter.new(t)
        gz.print("foo")
        gz.close
        File.open(t.path, 'ab') do |f|
          gz = Zlib::GzipWriter.new(f)
          gz.print("bar")
          gz.close
        end

        results = []
        File.open(t.path, 'rb') do |f|
          Zlib::GzipReader.zcat(f) do |str|
            results << str
          end
        end
        assert_equal(["foo", "bar"], results)

        results = File.open(t.path, 'rb') do |f|
          Zlib::GzipReader.zcat(f)
        end
        assert_equal("foobar", results)
      }
    end

    def test_to_io
      Tempfile.create("test_zlib_gzip_file_to_io") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_kind_of(IO, f.to_io)
        end
      }
    end

    def test_crc
      Tempfile.create("test_zlib_gzip_file_crc") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          f.read
          assert_equal(0x8c736521, f.crc)
        end
      }
    end

    def test_mtime
      tim = Time.now

      Tempfile.create("test_zlib_gzip_file_mtime") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) do |gz|
          gz.mtime = -1
          gz.mtime = tim
          gz.print("foo")
          gz.flush
          assert_raise(Zlib::GzipFile::Error) { gz.mtime = Time.now }
        end

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(tim.to_i, f.mtime.to_i)
        end
      }
    end

    def test_zero_mtime
      sio = StringIO.new
      gz = Zlib::GzipWriter.new(sio)
      gz.mtime = 0
      gz.write("Hi")
      gz.close
      reading_io = StringIO.new(sio.string)
      reader = Zlib::GzipReader.new(reading_io)
      assert_equal(0, reader.mtime.to_i)
    end

    def test_level
      Tempfile.create("test_zlib_gzip_file_level") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(Zlib::DEFAULT_COMPRESSION, f.level)
        end
      }
    end

    def test_os_code
      Tempfile.create("test_zlib_gzip_file_os_code") {|t|
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(Zlib::OS_CODE, f.os_code)
        end
      }
    end

    def test_orig_name
      Tempfile.create("test_zlib_gzip_file_orig_name") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) do |gz|
          gz.orig_name = "foobarbazqux\0quux"
          gz.print("foo")
          gz.flush
          assert_raise(Zlib::GzipFile::Error) { gz.orig_name = "quux" }
        end

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foobarbazqux", f.orig_name)
        end
      }
    end

    def test_comment
      Tempfile.create("test_zlib_gzip_file_comment") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) do |gz|
          gz.comment = "foobarbazqux\0quux"
          gz.print("foo")
          gz.flush
          assert_raise(Zlib::GzipFile::Error) { gz.comment = "quux" }
        end

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foobarbazqux", f.comment)
        end
      }
    end

    def test_lineno
      Tempfile.create("test_zlib_gzip_file_lineno") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\nqux\n") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal([0, "foo\n"], [f.lineno, f.gets])
          assert_equal([1, "bar\n"], [f.lineno, f.gets])
          f.lineno = 1000
          assert_equal([1000, "baz\n"], [f.lineno, f.gets])
          assert_equal([1001, "qux\n"], [f.lineno, f.gets])
        end
      }
    end

    def test_closed_p
      Tempfile.create("test_zlib_gzip_file_closed_p") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(false, f.closed?)
          f.read
          assert_equal(false, f.closed?)
          f.close
          assert_equal(true, f.closed?)
        end
      }
    end

    def test_sync
      Tempfile.create("test_zlib_gzip_file_sync") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          f.sync = true
          assert_equal(true, f.sync)
          f.read
          f.sync = false
          assert_equal(false, f.sync)
        end
      }
    end

    def test_pos
      Tempfile.create("test_zlib_gzip_file_pos") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) do |gz|
          gz.print("foo")
          gz.flush
          assert_equal(3, gz.tell)
        end
      }
    end

    def test_path
      Tempfile.create("test_zlib_gzip_file_path") {|t|
        t.close

        gz = Zlib::GzipWriter.open(t.path)
        gz.print("foo")
        assert_equal(t.path, gz.path)
        gz.close
        assert_equal(t.path, gz.path)

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(t.path, f.path)
          f.close
          assert_equal(t.path, f.path)
        end

        s = "".dup
        sio = StringIO.new(s)
        gz = Zlib::GzipWriter.new(sio)
        gz.print("foo")
        assert_raise(NoMethodError) { gz.path }
        gz.close

        sio = StringIO.new(s)
        gz = Zlib::GzipReader.new(sio)
        assert_raise(NoMethodError) { gz.path }
        gz.close
      }
    end

    if defined? File::TMPFILE
      def test_path_tmpfile
        sio = StringIO.new("".dup, 'w')
        gz = Zlib::GzipWriter.new(sio)
        gz.write "hi"
        gz.close

        File.open(Dir.mktmpdir, File::RDWR | File::TMPFILE) do |io|
          io.write sio.string
          io.rewind

          gz0 = Zlib::GzipWriter.new(io)
          gz1 = Zlib::GzipReader.new(io)

          if IO.method_defined?(:path)
            assert_nil gz0.path
            assert_nil gz1.path
          else
            assert_raise(NoMethodError) { gz0.path }
            assert_raise(NoMethodError) { gz1.path }
          end

          gz0.close
          gz1.close
        end
      rescue Errno::EINVAL
        omit 'O_TMPFILE not supported (EINVAL)'
      rescue Errno::EISDIR
        omit 'O_TMPFILE not supported (EISDIR)'
      rescue Errno::EOPNOTSUPP
        omit 'O_TMPFILE not supported (EOPNOTSUPP)'
      end
    end
  end

  class TestZlibGzipReader < Test::Unit::TestCase
    D0 = "\037\213\010\000S`\017A\000\003\003\000\000\000\000\000\000\000\000\000"
    def test_read0
      assert_equal("", Zlib::GzipReader.new(StringIO.new(D0)).read(0))
    end

    def test_ungetc
      s = "".dup
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
      s = "".dup
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

    def test_ungetc_at_start_of_file
      s = "".dup
      w = Zlib::GzipWriter.new(StringIO.new(s))
      w << "abc"
      w.close
      r = Zlib::GzipReader.new(StringIO.new(s))

      r.ungetc ?!

      assert_equal(-1, r.pos, "[ruby-core:81488][Bug #13616]")
    end

    def test_open
      Tempfile.create("test_zlib_gzip_reader_open") {|t|
        t.close
        e = assert_raise(Zlib::GzipFile::Error) {
          Zlib::GzipReader.open(t.path)
        }
        assert_equal("not in gzip format", e.message)
        assert_nil(e.input)
        open(t.path, "wb") {|f| f.write("foo")}
        e = assert_raise(Zlib::GzipFile::Error) {
          Zlib::GzipReader.open(t.path)
        }
        assert_equal("not in gzip format", e.message)
        assert_equal("foo", e.input)
        open(t.path, "wb") {|f| f.write("foobarzothoge")}
        e = assert_raise(Zlib::GzipFile::Error) {
          Zlib::GzipReader.open(t.path)
        }
        assert_equal("not in gzip format", e.message)
        assert_equal("foobarzothoge", e.input)

        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        assert_raise(ArgumentError) { Zlib::GzipReader.open }

        assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })

        f = Zlib::GzipReader.open(t.path)
        begin
          assert_equal("foo", f.read)
        ensure
          f.close
        end
      }
    end

    def test_rewind
      bug8467 = '[ruby-core:55220] [Bug #8467]'
      Tempfile.create("test_zlib_gzip_reader_rewind") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foo", f.read)
          f.rewind
          assert_equal("foo", f.read)

          f.rewind
          bytes = []
          f.each_byte { |b| bytes << b }
          assert_equal "foo".bytes.to_a, bytes, '[Bug #10101]'
        end
        open(t.path, "rb") do |f|
          gz = Zlib::GzipReader.new(f)
          gz.rewind
          assert_equal(["foo"], gz.to_a, bug8467)
        end
      }
    end

    def test_unused
      Tempfile.create("test_zlib_gzip_reader_unused") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(nil, f.unused)
          assert_equal("foo", f.read(3))
          assert_equal(nil, f.unused)
          assert_equal("bar", f.read)
          assert_equal(nil, f.unused)
        end
      }
    end

    def test_unused2
      zio = StringIO.new

      io = Zlib::GzipWriter.new zio
      io.write 'aaaa'
      io.finish

      io = Zlib::GzipWriter.new zio
      io.write 'bbbb'
      io.finish

      zio.rewind

      io = Zlib::GzipReader.new zio
      assert_equal('aaaa', io.read)
      unused = io.unused
      assert_equal(24, unused.bytesize)
      io.finish

      zio.pos -= unused.length

      io = Zlib::GzipReader.new zio
      assert_equal('bbbb', io.read)
      assert_equal(nil, io.unused)
      io.finish
    end

    def test_read
      Tempfile.create("test_zlib_gzip_reader_read") {|t|
        t.close
        str = "\u3042\u3044\u3046"
        Zlib::GzipWriter.open(t.path) {|gz| gz.print(str) }

        Zlib::GzipReader.open(t.path, encoding: "UTF-8") do |f|
          assert_raise(ArgumentError) { f.read(-1) }
          assert_equal(str, f.read)
        end
      }
    end

    def test_readpartial
      Tempfile.create("test_zlib_gzip_reader_readpartial") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

        Zlib::GzipReader.open(t.path) do |f|
          assert("foo".start_with?(f.readpartial(3)))
        end

        Zlib::GzipReader.open(t.path) do |f|
          s = "".dup
          f.readpartial(3, s)
          assert("foo".start_with?(s))

          assert_raise(ArgumentError) { f.readpartial(-1) }
        end
      }
    end

    def test_getc
      Tempfile.create("test_zlib_gzip_reader_getc") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

        Zlib::GzipReader.open(t.path) do |f|
          "foobar".each_char {|c| assert_equal(c, f.getc) }
          assert_nil(f.getc)
        end
      }
    end

    def test_getbyte
      Tempfile.create("test_zlib_gzip_reader_getbyte") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

        Zlib::GzipReader.open(t.path) do |f|
          "foobar".each_byte {|c| assert_equal(c, f.getbyte) }
          assert_nil(f.getbyte)
        end
      }
    end

    def test_readchar
      Tempfile.create("test_zlib_gzip_reader_readchar") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

        Zlib::GzipReader.open(t.path) do |f|
          "foobar".each_byte {|c| assert_equal(c, f.readchar.ord) }
          assert_raise(EOFError) { f.readchar }
        end
      }
    end

    def test_each_byte
      Tempfile.create("test_zlib_gzip_reader_each_byte") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foobar") }

        Zlib::GzipReader.open(t.path) do |f|
          a = []
          f.each_byte {|c| a << c }
          assert_equal("foobar".each_byte.to_a, a)
        end
      }
    end

    def test_gets
      Tempfile.create("test_zlib_gzip_reader_gets") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foo\n", f.gets)
          assert_equal("bar\n", f.gets)
          assert_equal("baz\n", f.gets)
          assert_nil(f.gets)
        end

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foo\nbar\nbaz\n", f.gets(nil))
        end

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foo\n", f.gets(10))
          assert_equal("ba", f.gets(2))
          assert_equal("r\nb", f.gets(nil, 3))
          assert_equal("az\n", f.gets(nil, 10))
          assert_nil(f.gets)
        end
      }
    end

    def test_gets2
      Tempfile.create("test_zlib_gzip_reader_gets2") {|t|
        t.close
        ustrs = %W"\u{3042 3044 3046}\n \u{304b 304d 304f}\n \u{3055 3057 3059}\n"
        Zlib::GzipWriter.open(t.path) {|gz| gz.print(*ustrs) }

        Zlib::GzipReader.open(t.path, encoding: "UTF-8") do |f|
          assert_equal(ustrs[0], f.gets)
          assert_equal(ustrs[1], f.gets)
          assert_equal(ustrs[2], f.gets)
          assert_nil(f.gets)
        end

        Zlib::GzipReader.open(t.path, encoding: "UTF-8") do |f|
          assert_equal(ustrs.join(''), f.gets(nil))
        end

        Zlib::GzipReader.open(t.path, encoding: "UTF-8") do |f|
          assert_equal(ustrs[0], f.gets(20))
          assert_equal(ustrs[1][0,2], f.gets(5))
          assert_equal(ustrs[1][2..-1]+ustrs[2][0,1], f.gets(nil, 5))
          assert_equal(ustrs[2][1..-1], f.gets(nil, 20))
          assert_nil(f.gets)
        end
      }
    end

    def test_readline
      Tempfile.create("test_zlib_gzip_reader_readline") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal("foo\n", f.readline)
          assert_equal("bar\n", f.readline)
          assert_equal("baz\n", f.readline)
          assert_raise(EOFError) { f.readline }
        end
      }
    end

    def test_each
      Tempfile.create("test_zlib_gzip_reader_each") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

        Zlib::GzipReader.open(t.path) do |f|
          a = ["foo\n", "bar\n", "baz\n"]
          f.each {|l| assert_equal(a.shift, l) }
        end
      }
    end

    def test_readlines
      Tempfile.create("test_zlib_gzip_reader_readlines") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo\nbar\nbaz\n") }

        Zlib::GzipReader.open(t.path) do |f|
          assert_equal(["foo\n", "bar\n", "baz\n"], f.readlines)
        end
      }
    end

    def test_reader_wrap
      Tempfile.create("test_zlib_gzip_reader_wrap") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }
        f = open(t.path)
        f.binmode
        assert_equal("foo", Zlib::GzipReader.wrap(f) {|gz| gz.read })
        assert(f.closed?)
      }
    end

    def test_corrupted_header
      gz = Zlib::GzipWriter.new(StringIO.new(s = "".dup))
      gz.orig_name = "X"
      gz.comment = "Y"
      gz.print("foo")
      gz.finish
      # 14: magic(2) + method(1) + flag(1) + mtime(4) + exflag(1) + os(1) + orig_name(2) + comment(2)
      1.upto(14) do |idx|
        assert_raise(Zlib::GzipFile::Error, idx) do
          Zlib::GzipReader.new(StringIO.new(s[0, idx])).read
        end
      end
    end

    def test_encoding
      Tempfile.create("test_zlib_gzip_reader_encoding") {|t|
        t.binmode
        content = (0..255).to_a.pack('c*')
        Zlib::GzipWriter.wrap(t) {|gz| gz.print(content) }

        read_all = Zlib::GzipReader.open(t.path) do |gz|
          assert_equal(Encoding.default_external, gz.external_encoding)
          gz.read
        end
        assert_equal(Encoding.default_external, read_all.encoding)

        # chunks are in BINARY regardless of encoding settings
        read_size = Zlib::GzipReader.open(t.path) {|gz| gz.read(1024) }
        assert_equal(Encoding::ASCII_8BIT, read_size.encoding)
        assert_equal(content, read_size)
      }
    end

    def test_double_close
      Tempfile.create("test_zlib_gzip_reader_close") {|t|
        t.binmode
        content = "foo"
        Zlib::GzipWriter.wrap(t) {|gz| gz.print(content) }
        r = Zlib::GzipReader.open(t.path)
        assert_equal(content, r.read)
        assert_nothing_raised { r.close }
        assert_nothing_raised { r.close }
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

    def test_open
      assert_raise(ArgumentError) { Zlib::GzipWriter.open }

      Tempfile.create("test_zlib_gzip_writer_open") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }
        assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })

        f = Zlib::GzipWriter.open(t.path)
        begin
          f.print("bar")
        ensure
          f.close
        end
        assert_equal("bar", Zlib::GzipReader.open(t.path) {|gz| gz.read })

        assert_raise(Zlib::StreamError) { Zlib::GzipWriter.open(t.path, 10000) }
      }
    end

    def test_write
      Tempfile.create("test_zlib_gzip_writer_write") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.print("foo") }
        assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })

        o = Object.new
        def o.to_s; "bar"; end
        Zlib::GzipWriter.open(t.path) {|gz| gz.print(o) }
        assert_equal("bar", Zlib::GzipReader.open(t.path) {|gz| gz.read })
      }
    end

    def test_putc
      Tempfile.create("test_zlib_gzip_writer_putc") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.putc(?x) }
        assert_equal("x", Zlib::GzipReader.open(t.path) {|gz| gz.read })

        # todo: multibyte char
      }
    end

    def test_puts
      Tempfile.create("test_zlib_gzip_writer_puts") {|t|
        t.close
        Zlib::GzipWriter.open(t.path) {|gz| gz.puts("foo") }
        assert_equal("foo\n", Zlib::GzipReader.open(t.path) {|gz| gz.read })
      }
    end

    def test_writer_wrap
      Tempfile.create("test_zlib_gzip_writer_wrap") {|t|
        t.binmode
        Zlib::GzipWriter.wrap(t) {|gz| gz.print("foo") }
        assert_equal("foo", Zlib::GzipReader.open(t.path) {|gz| gz.read })
      }
    end

    def test_double_close
      Tempfile.create("test_zlib_gzip_reader_close") {|t|
        t.binmode
        w = Zlib::GzipWriter.wrap(t)
        assert_nothing_raised { w.close }
        assert_nothing_raised { w.close }
      }
    end

    def test_zlib_writer_buffered_write
      bug15356 = '[ruby-core:90346] [Bug #15356]'.freeze
      fixes = 'r61631 (commit a55abcc0ca6f628fc05304f81e5a044d65ab4a68)'.freeze
      ary = []
      def ary.write(*args)
        self.concat(args)
      end
      gz = Zlib::GzipWriter.new(ary)
      gz.write(bug15356)
      gz.write("\n")
      gz.write(fixes)
      gz.close
      assert_not_predicate ary, :empty?
      exp = [ bug15356, fixes ]
      assert_equal exp, Zlib.gunzip(ary.join('')).split("\n")
    end
  end

  class TestZlib < Test::Unit::TestCase
    def test_version
      assert_instance_of(String, Zlib.zlib_version)
    end

    def test_adler32
      assert_equal(0x00000001, Zlib.adler32)
      assert_equal(0x02820145, Zlib.adler32("foo"))
      assert_equal(0x02820145, Zlib.adler32("o", Zlib.adler32("fo")))
      assert_equal(0x8a62c964, Zlib.adler32("abc\x01\x02\x03" * 10000))
      assert_equal(0x97d1a9f7, Zlib.adler32("p", -305419897))
      Tempfile.create("test_zlib_gzip_file_to_io") {|t|
        File.binwrite(t.path, "foo")
        t.rewind
        assert_equal(0x02820145, Zlib.adler32(t))

        t.rewind
        crc = Zlib.adler32(t.read(2))
        assert_equal(0x02820145, Zlib.adler32(t, crc))

        File.binwrite(t.path, "abc\x01\x02\x03" * 10000)
        t.rewind
        assert_equal(0x8a62c964, Zlib.adler32(t))
      }
    end

    def test_adler32_combine
      one = Zlib.adler32("fo")
      two = Zlib.adler32("o")
      begin
        assert_equal(0x02820145, Zlib.adler32_combine(one, two, 1))
      rescue NotImplementedError
        omit "adler32_combine is not implemented"
      rescue Test::Unit::AssertionFailedError
        if /aix/ =~ RUBY_PLATFORM
          omit "zconf.h in zlib does not handle _LARGE_FILES in AIX. Skip until it is fixed"
        end
        raise $!
      end
    end

    def test_crc32
      assert_equal(0x00000000, Zlib.crc32)
      assert_equal(0x8c736521, Zlib.crc32("foo"))
      assert_equal(0x8c736521, Zlib.crc32("o", Zlib.crc32("fo")))
      assert_equal(0x07f0d68f, Zlib.crc32("abc\x01\x02\x03" * 10000))
      assert_equal(0xf136439b, Zlib.crc32("p", -305419897))
      Tempfile.create("test_zlib_gzip_file_to_io") {|t|
        File.binwrite(t.path, "foo")
        t.rewind
        assert_equal(0x8c736521, Zlib.crc32(t))

        t.rewind
        crc = Zlib.crc32(t.read(2))
        assert_equal(0x8c736521, Zlib.crc32(t, crc))

        File.binwrite(t.path, "abc\x01\x02\x03" * 10000)
        t.rewind
        assert_equal(0x07f0d68f, Zlib.crc32(t))
      }
    end

    def test_crc32_combine
      one = Zlib.crc32("fo")
      two = Zlib.crc32("o")
      begin
        assert_equal(0x8c736521, Zlib.crc32_combine(one, two, 1))
      rescue NotImplementedError
        omit "crc32_combine is not implemented"
      rescue Test::Unit::AssertionFailedError
        if /aix/ =~ RUBY_PLATFORM
          omit "zconf.h in zlib does not handle _LARGE_FILES in AIX. Skip until it is fixed"
        end
        raise $!
      end
    end

    def test_crc_table
      t = Zlib.crc_table
      assert_instance_of(Array, t)
      t.each {|x| assert_kind_of(Integer, x) }
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

    def test_deflate
      s = Zlib::Deflate.deflate("foo")
      assert_equal("foo", Zlib::Inflate.inflate(s))

      assert_raise(Zlib::StreamError) { Zlib::Deflate.deflate("foo", 10000) }
    end

    def test_deflate_stream
      r = Random.new 0

      deflated = ''.dup

      Zlib.deflate(r.bytes(20000)) do |chunk|
        deflated << chunk
      end

      assert_equal 20016, deflated.length
    end

    def test_gzip
      actual = Zlib.gzip("foo".freeze)
      actual[4, 4] = "\x00\x00\x00\x00" # replace mtime
      actual[9] = "\xff" # replace OS
      expected = %w[1f8b08000000000000ff4bcbcf07002165738c03000000].pack("H*")
      assert_equal expected, actual

      actual = Zlib.gzip("foo".freeze, level: 0)
      actual[4, 4] = "\x00\x00\x00\x00" # replace mtime
      actual[9] = "\xff" # replace OS
      expected = %w[1f8b08000000000000ff010300fcff666f6f2165738c03000000].pack("H*")
      assert_equal expected, actual

      actual = Zlib.gzip("foo".freeze, level: 9)
      actual[4, 4] = "\x00\x00\x00\x00" # replace mtime
      actual[9] = "\xff" # replace OS
      expected = %w[1f8b08000000000002ff4bcbcf07002165738c03000000].pack("H*")
      assert_equal expected, actual

      actual = Zlib.gzip("foo".freeze, level: 9, strategy: Zlib::FILTERED)
      actual[4, 4] = "\x00\x00\x00\x00" # replace mtime
      actual[9] = "\xff" # replace OS
      expected = %w[1f8b08000000000002ff4bcbcf07002165738c03000000].pack("H*")
      assert_equal expected, actual
    end

    def test_gunzip
      src = %w[1f8b08000000000000034bcbcf07002165738c03000000].pack("H*")
      assert_equal 'foo', Zlib.gunzip(src.freeze)

      src = %w[1f8b08000000000000034bcbcf07002165738c03000001].pack("H*")
      assert_raise(Zlib::GzipFile::LengthError){ Zlib.gunzip(src) }

      src = %w[1f8b08000000000000034bcbcf07002165738d03000000].pack("H*")
      assert_raise(Zlib::GzipFile::CRCError){ Zlib.gunzip(src) }

      src = %w[1f8b08000000000000034bcbcf07002165738d030000].pack("H*")
      assert_raise(Zlib::GzipFile::Error){ Zlib.gunzip(src) }

      src = %w[1f8b08000000000000034bcbcf0700].pack("H*")
      assert_raise(Zlib::GzipFile::NoFooter){ Zlib.gunzip(src) }

      src = %w[1f8b080000000000000].pack("H*")
      assert_raise(Zlib::GzipFile::Error){ Zlib.gunzip(src) }
    end

    # Zlib.gunzip input is always considered a binary string, regardless of its String#encoding.
    def test_gunzip_encoding
      #                vvvvvvvv = mtime, but valid UTF-8 string of U+0080
      src = %w[1f8b0800c28000000003cb48cdc9c9070086a6103605000000].pack("H*").force_encoding('UTF-8')
      assert_equal 'hello', Zlib.gunzip(src.freeze)
    end

    def test_gunzip_no_memory_leak
      assert_no_memory_leak(%[-rzlib], "#{<<~"{#"}", "#{<<~'};'}")
      d = Zlib.gzip("data")
      {#
        10_000.times {Zlib.gunzip(d)}
      };
    end
  end
end
