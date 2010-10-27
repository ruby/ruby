require 'test/unit'
require 'tmpdir'
require "fcntl"
require 'io/nonblock'
require 'socket'
require 'stringio'
require 'timeout'
require 'tempfile'
require_relative 'envutil'

class TestIO < Test::Unit::TestCase
  def have_close_on_exec?
    begin
      $stdin.close_on_exec?
      true
    rescue NotImplementedError
      false
    end
  end

  def have_nonblock?
    IO.method_defined?("nonblock=")
  end

  def pipe(wp, rp)
    re, we = nil, nil
    r, w = IO.pipe
    rt = Thread.new do
      begin
        rp.call(r)
      rescue Exception
        r.close
        re = $!
      end
    end
    wt = Thread.new do
      begin
        wp.call(w)
      rescue Exception
        w.close
        we = $!
      end
    end
    flunk("timeout") unless wt.join(10) && rt.join(10)
  ensure
    w.close unless !w || w.closed?
    r.close unless !r || r.closed?
    (wt.kill; wt.join) if wt
    (rt.kill; rt.join) if rt
    raise we if we
    raise re if re
  end

  def with_pipe
    r, w = IO.pipe
    begin
      yield r, w
    ensure
      r.close unless r.closed?
      w.close unless w.closed?
    end
  end

  def with_read_pipe(content)
    pipe(proc do |w|
      w << content
      w.close
    end, proc do |r|
      yield r
    end)
  end

  def mkcdtmpdir
    Dir.mktmpdir {|d|
      Dir.chdir(d) {
        yield
      }
    }
  end

  def test_pipe
    r, w = IO.pipe
    assert_instance_of(IO, r)
    assert_instance_of(IO, w)
    [
      Thread.start{
        w.print "abc"
        w.close
      },
      Thread.start{
        assert_equal("abc", r.read)
        r.close
      }
    ].each{|thr| thr.join}
  end

  def test_pipe_block
    x = nil
    ret = IO.pipe {|r, w|
      x = [r,w]
      assert_instance_of(IO, r)
      assert_instance_of(IO, w)
      [
        Thread.start do
          w.print "abc"
          w.close
        end,
        Thread.start do
          assert_equal("abc", r.read)
        end
      ].each{|thr| thr.join}
      assert(!r.closed?)
      assert(w.closed?)
      :foooo
    }
    assert_equal(:foooo, ret)
    assert(x[0].closed?)
    assert(x[1].closed?)
  end

  def test_pipe_block_close
    4.times {|i|
      x = nil
      IO.pipe {|r, w|
        x = [r,w]
        r.close if (i&1) == 0
        w.close if (i&2) == 0
      }
      assert(x[0].closed?)
      assert(x[1].closed?)
    }
  end

  def test_gets_rs
    # default_rs
    pipe(proc do |w|
      w.print "aaa\nbbb\n"
      w.close
    end, proc do |r|
      assert_equal "aaa\n", r.gets
      assert_equal "bbb\n", r.gets
      assert_nil r.gets
      r.close
    end)

    # nil
    pipe(proc do |w|
      w.print "a\n\nb\n\n"
      w.close
    end, proc do |r|
      assert_equal "a\n\nb\n\n", r.gets(nil)
      assert_nil r.gets("")
      r.close
    end)

    # "\377"
    pipe(proc do |w|
      w.print "\377xyz"
      w.close
    end, proc do |r|
      r.binmode
      assert_equal("\377", r.gets("\377"), "[ruby-dev:24460]")
      r.close
    end)

    # ""
    pipe(proc do |w|
      w.print "a\n\nb\n\n"
      w.close
    end, proc do |r|
      assert_equal "a\n\n", r.gets(""), "[ruby-core:03771]"
      assert_equal "b\n\n", r.gets("")
      assert_nil r.gets("")
      r.close
    end)
  end

  def test_gets_limit_extra_arg
    pipe(proc do |w|
      w << "0123456789\n0123456789"
      w.close
    end, proc do |r|
      assert_equal("0123456789\n0", r.gets(nil, 12))
      assert_raise(TypeError) { r.gets(3,nil) }
    end)
  end

  # This test cause SEGV.
  def test_ungetc
    pipe(proc do |w|
      w.close
    end, proc do |r|
      s = "a" * 1000
      assert_raise(IOError, "[ruby-dev:31650]") { 200.times { r.ungetc s } }
    end)
  end

  def test_ungetbyte
    t = make_tempfile
    t.open
    t.binmode
    t.ungetbyte(0x41)
    assert_equal(-1, t.pos)
    assert_equal(0x41, t.getbyte)
    t.rewind
    assert_equal(0, t.pos)
    t.ungetbyte("qux")
    assert_equal(-3, t.pos)
    assert_equal("quxfoo\n", t.gets)
    assert_equal(4, t.pos)
    t.set_encoding("utf-8")
    t.ungetbyte(0x89)
    t.ungetbyte(0x8e)
    t.ungetbyte("\xe7")
    t.ungetbyte("\xe7\xb4\x85")
    assert_equal(-2, t.pos)
    assert_equal("\u7d05\u7389bar\n", t.gets)
  end

  def test_each_byte
    pipe(proc do |w|
      w << "abc def"
      w.close
    end, proc do |r|
      r.each_byte {|byte| break if byte == 32 }
      assert_equal("def", r.read, "[ruby-dev:31659]")
    end)
  end

  def test_each_codepoint
    t = make_tempfile
    bug2959 = '[ruby-core:28650]'
    a = ""
    File.open(t, 'rt') {|f|
      f.each_codepoint {|c| a << c}
    }
    assert_equal("foo\nbar\nbaz\n", a, bug2959)
  end

  def test_rubydev33072
    t = make_tempfile
    path = t.path
    t.close!
    assert_raise(Errno::ENOENT, "[ruby-dev:33072]") do
      File.read(path, nil, nil, {})
    end
  end

  def test_copy_stream
    mkcdtmpdir {

      content = "foobar"
      File.open("src", "w") {|f| f << content }
      ret = IO.copy_stream("src", "dst")
      assert_equal(content.bytesize, ret)
      assert_equal(content, File.read("dst"))

      # overwrite by smaller file.
      content = "baz"
      File.open("src", "w") {|f| f << content }
      ret = IO.copy_stream("src", "dst")
      assert_equal(content.bytesize, ret)
      assert_equal(content, File.read("dst"))

      ret = IO.copy_stream("src", "dst", 2)
      assert_equal(2, ret)
      assert_equal(content[0,2], File.read("dst"))

      ret = IO.copy_stream("src", "dst", 0)
      assert_equal(0, ret)
      assert_equal("", File.read("dst"))

      ret = IO.copy_stream("src", "dst", nil, 1)
      assert_equal(content.bytesize-1, ret)
      assert_equal(content[1..-1], File.read("dst"))

      assert_raise(Errno::ENOENT) {
        IO.copy_stream("nodir/foo", "dst")
      }

      assert_raise(Errno::ENOENT) {
        IO.copy_stream("src", "nodir/bar")
      }

      pipe(proc do |w|
        ret = IO.copy_stream("src", w)
        assert_equal(content.bytesize, ret)
        w.close
      end, proc do |r|
        assert_equal(content, r.read)
      end)

      with_pipe {|r, w|
        w.close
        assert_raise(IOError) { IO.copy_stream("src", w) }
      }

      pipe_content = "abc"
      with_read_pipe(pipe_content) {|r|
        ret = IO.copy_stream(r, "dst")
        assert_equal(pipe_content.bytesize, ret)
        assert_equal(pipe_content, File.read("dst"))
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          w2.sync = false
          w2 << "def"
          ret = IO.copy_stream(r1, w2)
          assert_equal(2, ret)
          w2.close
        end, proc do |r2|
          assert_equal("defbc", r2.read)
        end)
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          w2.sync = false
          w2 << "def"
          ret = IO.copy_stream(r1, w2, 1)
          assert_equal(1, ret)
          w2.close
        end, proc do |r2|
          assert_equal("defb", r2.read)
        end)
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          ret = IO.copy_stream(r1, w2)
          assert_equal(2, ret)
          w2.close
        end, proc do |r2|
          assert_equal("bc", r2.read)
        end)
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          ret = IO.copy_stream(r1, w2, 1)
          assert_equal(1, ret)
          w2.close
        end, proc do |r2|
          assert_equal("b", r2.read)
        end)
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          ret = IO.copy_stream(r1, w2, 0)
          assert_equal(0, ret)
          w2.close
        end, proc do |r2|
          assert_equal("", r2.read)
        end)
      }

      pipe(proc do |w1|
        w1 << "abc"
        w1 << "def"
        w1.close
      end, proc do |r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          ret = IO.copy_stream(r1, w2)
          assert_equal(5, ret)
          w2.close
        end, proc do |r2|
          assert_equal("bcdef", r2.read)
        end)
      end)

      pipe(proc do |w|
        ret = IO.copy_stream("src", w, 1, 1)
        assert_equal(1, ret)
        w.close
      end, proc do |r|
        assert_equal(content[1,1], r.read)
      end)

      if have_nonblock?
        with_read_pipe("abc") {|r1|
          assert_equal("a", r1.getc)
          with_pipe {|r2, w2|
            begin
              w2.nonblock = true
            rescue Errno::EBADF
              skip "nonblocking IO for pipe is not implemented"
              break
            end
            s = w2.syswrite("a" * 100000)
            t = Thread.new { sleep 0.1; r2.read }
            ret = IO.copy_stream(r1, w2)
            w2.close
            assert_equal(2, ret)
            assert_equal("a" * s + "bc", t.value)
          }
        }
      end

      bigcontent = "abc" * 123456
      File.open("bigsrc", "w") {|f| f << bigcontent }
      ret = IO.copy_stream("bigsrc", "bigdst")
      assert_equal(bigcontent.bytesize, ret)
      assert_equal(bigcontent, File.read("bigdst"))

      File.unlink("bigdst")
      ret = IO.copy_stream("bigsrc", "bigdst", nil, 100)
      assert_equal(bigcontent.bytesize-100, ret)
      assert_equal(bigcontent[100..-1], File.read("bigdst"))

      File.unlink("bigdst")
      ret = IO.copy_stream("bigsrc", "bigdst", 30000, 100)
      assert_equal(30000, ret)
      assert_equal(bigcontent[100, 30000], File.read("bigdst"))

      File.open("bigsrc") {|f|
        begin
          assert_equal(0, f.pos)
          ret = IO.copy_stream(f, "bigdst", nil, 10)
          assert_equal(bigcontent.bytesize-10, ret)
          assert_equal(bigcontent[10..-1], File.read("bigdst"))
          assert_equal(0, f.pos)
          ret = IO.copy_stream(f, "bigdst", 40, 30)
          assert_equal(40, ret)
          assert_equal(bigcontent[30, 40], File.read("bigdst"))
          assert_equal(0, f.pos)
        rescue NotImplementedError
          #skip "pread(2) is not implemtented."
        end
      }

      with_pipe {|r, w|
        w.close
        assert_raise(IOError) { IO.copy_stream("src", w) }
      }

      megacontent = "abc" * 1234567
      File.open("megasrc", "w") {|f| f << megacontent }

      if have_nonblock?
        with_pipe {|r1, w1|
          with_pipe {|r2, w2|
            begin
              r1.nonblock = true
              w2.nonblock = true
            rescue Errno::EBADF
              skip "nonblocking IO for pipe is not implemented"
            end
            t1 = Thread.new { w1 << megacontent; w1.close }
            t2 = Thread.new { r2.read }
            ret = IO.copy_stream(r1, w2)
            assert_equal(megacontent.bytesize, ret)
            w2.close
            t1.join
            assert_equal(megacontent, t2.value)
          }
        }
      end

      with_pipe {|r1, w1|
        with_pipe {|r2, w2|
          t1 = Thread.new { w1 << megacontent; w1.close }
          t2 = Thread.new { r2.read }
          ret = IO.copy_stream(r1, w2)
          assert_equal(megacontent.bytesize, ret)
          w2.close
          t1.join
          assert_equal(megacontent, t2.value)
        }
      }

      with_pipe {|r, w|
        t = Thread.new { r.read }
        ret = IO.copy_stream("megasrc", w)
        assert_equal(megacontent.bytesize, ret)
        w.close
        assert_equal(megacontent, t.value)
      }
    }
  end

  def test_copy_stream_rbuf
    mkcdtmpdir {
      begin
        pipe(proc do |w|
          File.open("foo", "w") {|f| f << "abcd" }
          File.open("foo") {|f|
            f.read(1)
            assert_equal(3, IO.copy_stream(f, w, 10, 1))
          }
          w.close
        end, proc do |r|
          assert_equal("bcd", r.read)
        end)
      rescue NotImplementedError
        skip "pread(2) is not implemtented."
      end
    }
  end

  def with_socketpair
    s1, s2 = UNIXSocket.pair
    begin
      yield s1, s2
    ensure
      s1.close unless s1.closed?
      s2.close unless s2.closed?
    end
  end

  def test_copy_stream_socket
    return unless defined? UNIXSocket
    mkcdtmpdir {

      content = "foobar"
      File.open("src", "w") {|f| f << content }

      with_socketpair {|s1, s2|
        ret = IO.copy_stream("src", s1)
        assert_equal(content.bytesize, ret)
        s1.close
        assert_equal(content, s2.read)
      }

      bigcontent = "abc" * 123456
      File.open("bigsrc", "w") {|f| f << bigcontent }

      with_socketpair {|s1, s2|
        t = Thread.new { s2.read }
        ret = IO.copy_stream("bigsrc", s1)
        assert_equal(bigcontent.bytesize, ret)
        s1.close
        result = t.value
        assert_equal(bigcontent, result)
      }

      with_socketpair {|s1, s2|
        t = Thread.new { s2.read }
        ret = IO.copy_stream("bigsrc", s1, 10000)
        assert_equal(10000, ret)
        s1.close
        result = t.value
        assert_equal(bigcontent[0,10000], result)
      }

      File.open("bigsrc") {|f|
        assert_equal(0, f.pos)
        with_socketpair {|s1, s2|
          t = Thread.new { s2.read }
          ret = IO.copy_stream(f, s1, nil, 100)
          assert_equal(bigcontent.bytesize-100, ret)
          assert_equal(0, f.pos)
          s1.close
          result = t.value
          assert_equal(bigcontent[100..-1], result)
        }
      }

      File.open("bigsrc") {|f|
        assert_equal(bigcontent[0,100], f.read(100))
        assert_equal(100, f.pos)
        with_socketpair {|s1, s2|
          t = Thread.new { s2.read }
          ret = IO.copy_stream(f, s1)
          assert_equal(bigcontent.bytesize-100, ret)
          assert_equal(bigcontent.length, f.pos)
          s1.close
          result = t.value
          assert_equal(bigcontent[100..-1], result)
        }
      }

      megacontent = "abc" * 1234567
      File.open("megasrc", "w") {|f| f << megacontent }

      if have_nonblock?
        with_socketpair {|s1, s2|
          begin
            s1.nonblock = true
          rescue Errno::EBADF
            skip "nonblocking IO for pipe is not implemented"
          end
          t = Thread.new { s2.read }
          ret = IO.copy_stream("megasrc", s1)
          assert_equal(megacontent.bytesize, ret)
          s1.close
          result = t.value
          assert_equal(megacontent, result)
        }
      end
    }
  end

  def test_copy_stream_strio
    src = StringIO.new("abcd")
    dst = StringIO.new
    ret = IO.copy_stream(src, dst)
    assert_equal(4, ret)
    assert_equal("abcd", dst.string)
    assert_equal(4, src.pos)
  end

  def test_copy_stream_strio_len
    src = StringIO.new("abcd")
    dst = StringIO.new
    ret = IO.copy_stream(src, dst, 3)
    assert_equal(3, ret)
    assert_equal("abc", dst.string)
    assert_equal(3, src.pos)
  end

  def test_copy_stream_strio_off
    src = StringIO.new("abcd")
    with_pipe {|r, w|
      assert_raise(ArgumentError) {
        IO.copy_stream(src, w, 3, 1)
      }
    }
  end

  def test_copy_stream_fname_to_strio
    mkcdtmpdir {
      File.open("foo", "w") {|f| f << "abcd" }
      src = "foo"
      dst = StringIO.new
      ret = IO.copy_stream(src, dst, 3)
      assert_equal(3, ret)
      assert_equal("abc", dst.string)
    }
  end

  def test_copy_stream_strio_to_fname
    mkcdtmpdir {
      # StringIO to filename
      src = StringIO.new("abcd")
      ret = IO.copy_stream(src, "fooo", 3)
      assert_equal(3, ret)
      assert_equal("abc", File.read("fooo"))
      assert_equal(3, src.pos)
    }
  end

  def test_copy_stream_io_to_strio
    mkcdtmpdir {
      # IO to StringIO
      File.open("bar", "w") {|f| f << "abcd" }
      File.open("bar") {|src|
        dst = StringIO.new
        ret = IO.copy_stream(src, dst, 3)
        assert_equal(3, ret)
        assert_equal("abc", dst.string)
        assert_equal(3, src.pos)
      }
    }
  end

  def test_copy_stream_strio_to_io
    mkcdtmpdir {
      # StringIO to IO
      src = StringIO.new("abcd")
      ret = File.open("baz", "w") {|dst|
        IO.copy_stream(src, dst, 3)
      }
      assert_equal(3, ret)
      assert_equal("abc", File.read("baz"))
      assert_equal(3, src.pos)
    }
  end

  class Rot13IO
    def initialize(io)
      @io = io
    end

    def readpartial(*args)
      ret = @io.readpartial(*args)
      ret.tr!('a-zA-Z', 'n-za-mN-ZA-M')
      ret
    end

    def write(str)
      @io.write(str.tr('a-zA-Z', 'n-za-mN-ZA-M'))
    end

    def to_io
      @io
    end
  end

  def test_copy_stream_io_to_rot13
    mkcdtmpdir {
      File.open("bar", "w") {|f| f << "vex" }
      File.open("bar") {|src|
        File.open("baz", "w") {|dst0|
          dst = Rot13IO.new(dst0)
          ret = IO.copy_stream(src, dst, 3)
          assert_equal(3, ret)
        }
        assert_equal("irk", File.read("baz"))
      }
    }
  end

  def test_copy_stream_rot13_to_io
    mkcdtmpdir {
      File.open("bar", "w") {|f| f << "flap" }
      File.open("bar") {|src0|
        src = Rot13IO.new(src0)
        File.open("baz", "w") {|dst|
          ret = IO.copy_stream(src, dst, 4)
          assert_equal(4, ret)
        }
      }
      assert_equal("sync", File.read("baz"))
    }
  end

  def test_copy_stream_rot13_to_rot13
    mkcdtmpdir {
      File.open("bar", "w") {|f| f << "bin" }
      File.open("bar") {|src0|
        src = Rot13IO.new(src0)
        File.open("baz", "w") {|dst0|
          dst = Rot13IO.new(dst0)
          ret = IO.copy_stream(src, dst, 3)
          assert_equal(3, ret)
        }
      }
      assert_equal("bin", File.read("baz"))
    }
  end

  def test_copy_stream_strio_flush
    with_pipe {|r, w|
      w.sync = false
      w.write "zz"
      src = StringIO.new("abcd")
      IO.copy_stream(src, w)
      t = Thread.new {
        w.close
      }
      assert_equal("zzabcd", r.read)
      t.join
    }
  end

  def test_copy_stream_strio_rbuf
    pipe(proc do |w|
      w << "abcd"
      w.close
    end, proc do |r|
      assert_equal("a", r.read(1))
      sio = StringIO.new
      IO.copy_stream(r, sio)
      assert_equal("bcd", sio.string)
    end)
  end

  def test_copy_stream_src_wbuf
    mkcdtmpdir {
      pipe(proc do |w|
        File.open("foe", "w+") {|f|
          f.write "abcd\n"
          f.rewind
          f.write "xy"
          IO.copy_stream(f, w)
        }
        assert_equal("xycd\n", File.read("foe"))
        w.close
      end, proc do |r|
        assert_equal("cd\n", r.read)
        r.close
      end)
    }
  end

  def test_copy_stream_dst_rbuf
    mkcdtmpdir {
      pipe(proc do |w|
        w << "xyz"
        w.close
      end, proc do |r|
        File.open("fom", "w+b") {|f|
          f.write "abcd\n"
          f.rewind
          assert_equal("abc", f.read(3))
          f.ungetc "c"
          IO.copy_stream(r, f)
        }
        assert_equal("abxyz", File.read("fom"))
      end)
    }
  end

  def safe_4
    t = Thread.new do
      $SAFE = 4
      yield
    end
    unless t.join(10)
      t.kill
      flunk("timeout in safe_4")
    end
  end

  def ruby(*args)
    args = ['-e', '$>.write($<.read)'] if args.empty?
    ruby = EnvUtil.rubybin
    f = IO.popen([ruby] + args, 'r+')
    yield(f)
  ensure
    f.close unless !f || f.closed?
  end

  def test_try_convert
    assert_equal(STDOUT, IO.try_convert(STDOUT))
    assert_equal(nil, IO.try_convert("STDOUT"))
  end

  def test_ungetc2
    f = false
    pipe(proc do |w|
      0 until f
      w.write("1" * 10000)
      w.close
    end, proc do |r|
      r.ungetc("0" * 10000)
      f = true
      assert_equal("0" * 10000 + "1" * 10000, r.read)
    end)
  end

  def test_write_non_writable
    with_pipe do |r, w|
      assert_raise(IOError) do
        r.write "foobarbaz"
      end
    end
  end

  def test_dup
    ruby do |f|
      f2 = f.dup
      f.puts "foo"
      f2.puts "bar"
      f.close_write
      f2.close_write
      assert_equal("foo\nbar\n", f.read)
      assert_equal("", f2.read)
    end
  end

  def test_dup_many
    ruby('-e', <<-'End') {|f|
      ok = 0
      a = []
      begin
        loop {a << IO.pipe}
      rescue Errno::EMFILE, Errno::ENFILE, Errno::ENOMEM
        ok += 1
      end
      print "no" if ok != 1
      begin
        loop {a << [a[-1][0].dup, a[-1][1].dup]}
      rescue Errno::EMFILE, Errno::ENFILE, Errno::ENOMEM
        ok += 1
      end
      print "no" if ok != 2
      print "ok"
    End
      assert_equal("ok", f.read)
    }
  end

  def test_inspect
    with_pipe do |r, w|
      assert_match(/^#<IO:fd \d+>$/, r.inspect)
      assert_raise(SecurityError) do
        safe_4 { r.inspect }
      end
    end
  end

  def test_readpartial
    pipe(proc do |w|
      w.write "foobarbaz"
      w.close
    end, proc do |r|
      assert_raise(ArgumentError) { r.readpartial(-1) }
      assert_equal("fooba", r.readpartial(5))
      r.readpartial(5, s = "")
      assert_equal("rbaz", s)
    end)
  end

  def test_readpartial_lock
    with_pipe do |r, w|
      s = ""
      t = Thread.new { r.readpartial(5, s) }
      0 until s.size == 5
      assert_raise(RuntimeError) { s.clear }
      w.write "foobarbaz"
      w.close
      assert_equal("fooba", t.value)
    end
  end

  def test_readpartial_pos
    mkcdtmpdir {
      open("foo", "w") {|f| f << "abc" }
      open("foo") {|f|
        f.seek(0)
        assert_equal("ab", f.readpartial(2))
        assert_equal(2, f.pos)
      }
    }
  end

  def test_read
    pipe(proc do |w|
      w.write "foobarbaz"
      w.close
    end, proc do |r|
      assert_raise(ArgumentError) { r.read(-1) }
      assert_equal("fooba", r.read(5))
      r.read(nil, s = "")
      assert_equal("rbaz", s)
    end)
  end

  def test_read_lock
    with_pipe do |r, w|
      s = ""
      t = Thread.new { r.read(5, s) }
      0 until s.size == 5
      assert_raise(RuntimeError) { s.clear }
      w.write "foobarbaz"
      w.close
      assert_equal("fooba", t.value)
    end
  end

  def test_write_nonblock
    skip "IO#write_nonblock is not supported on file/pipe." if /mswin|bccwin|mingw/ =~ RUBY_PLATFORM
    pipe(proc do |w|
      w.write_nonblock(1)
      w.close
    end, proc do |r|
      assert_equal("1", r.read)
    end)
  end

  def test_read_nonblock_error
    return if !have_nonblock?
    skip "IO#read_nonblock is not supported on file/pipe." if /mswin|bccwin|mingw/ =~ RUBY_PLATFORM
    with_pipe {|r, w|
      begin
        r.read_nonblock 4096
      rescue Errno::EWOULDBLOCK
        assert_kind_of(IO::WaitReadable, $!)
      end
    }
  end

  def test_write_nonblock_error
    return if !have_nonblock?
    skip "IO#write_nonblock is not supported on file/pipe." if /mswin|bccwin|mingw/ =~ RUBY_PLATFORM
    with_pipe {|r, w|
      begin
        loop {
          w.write_nonblock "a"*100000
        }
      rescue Errno::EWOULDBLOCK
        assert_kind_of(IO::WaitWritable, $!)
      end
    }
  end

  def test_gets
    pipe(proc do |w|
      w.write "foobarbaz"
      w.close
    end, proc do |r|
      assert_equal("", r.gets(0))
      assert_equal("foobarbaz", s = r.gets(9))
    end)
  end

  def test_close_read
    ruby do |f|
      f.close_read
      f.write "foobarbaz"
      assert_raise(IOError) { f.read }
    end
  end

  def test_close_read_pipe
    with_pipe do |r, w|
      r.close_read
      assert_raise(Errno::EPIPE) { w.write "foobarbaz" }
    end
  end

  def test_close_read_security_error
    with_pipe do |r, w|
      assert_raise(SecurityError) do
        safe_4 { r.close_read }
      end
    end
  end

  def test_close_read_non_readable
    with_pipe do |r, w|
      assert_raise(IOError) do
        w.close_read
      end
    end
  end

  def test_close_write
    ruby do |f|
      f.write "foobarbaz"
      f.close_write
      assert_equal("foobarbaz", f.read)
    end
  end

  def test_close_write_security_error
    with_pipe do |r, w|
      assert_raise(SecurityError) do
        safe_4 { r.close_write }
      end
    end
  end

  def test_close_write_non_readable
    with_pipe do |r, w|
      assert_raise(IOError) do
        r.close_write
      end
    end
  end

  def test_pid
    r, w = IO.pipe
    assert_equal(nil, r.pid)
    assert_equal(nil, w.pid)

    pipe = IO.popen(EnvUtil.rubybin, "r+")
    pid1 = pipe.pid
    pipe.puts "p $$"
    pipe.close_write
    pid2 = pipe.read.chomp.to_i
    assert_equal(pid2, pid1)
    assert_equal(pid2, pipe.pid)
    pipe.close
    assert_raise(IOError) { pipe.pid }
  end

  def make_tempfile
    t = Tempfile.new("foo")
    t.binmode
    t.puts "foo"
    t.puts "bar"
    t.puts "baz"
    t.close
    t
  end

  def test_set_lineno
    t = make_tempfile

    ruby("-e", <<-SRC, t.path) do |f|
      open(ARGV[0]) do |f|
        p $.
        f.gets; p $.
        f.gets; p $.
        f.lineno = 1000; p $.
        f.gets; p $.
        f.gets; p $.
        f.rewind; p $.
        f.gets; p $.
        f.gets; p $.
        f.gets; p $.
        f.gets; p $.
      end
    SRC
      assert_equal("0,1,2,2,1001,1001,1001,1,2,3,3", f.read.chomp.gsub("\n", ","))
    end

    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      r.gets; assert_equal(1, $.)
      r.gets; assert_equal(2, $.)
      r.lineno = 1000; assert_equal(2, $.)
      r.gets; assert_equal(1001, $.)
      r.gets; assert_equal(1001, $.)
    end)
  end

  def test_readline
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      r.readline; assert_equal(1, $.)
      r.readline; assert_equal(2, $.)
      r.lineno = 1000; assert_equal(2, $.)
      r.readline; assert_equal(1001, $.)
      assert_raise(EOFError) { r.readline }
    end)
  end

  def test_each_char
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      a = []
      r.each_char {|c| a << c }
      assert_equal(%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"], a)
    end)
  end

  def test_lines
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      e = r.lines
      assert_equal("foo\n", e.next)
      assert_equal("bar\n", e.next)
      assert_equal("baz\n", e.next)
      assert_raise(StopIteration) { e.next }
    end)
  end

  def test_bytes
    pipe(proc do |w|
      w.binmode
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      e = r.bytes
      (%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"]).each do |c|
        assert_equal(c.ord, e.next)
      end
      assert_raise(StopIteration) { e.next }
    end)
  end

  def test_chars
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      e = r.chars
      (%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"]).each do |c|
        assert_equal(c, e.next)
      end
      assert_raise(StopIteration) { e.next }
    end)
  end

  def test_readbyte
    pipe(proc do |w|
      w.binmode
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      r.binmode
      (%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"]).each do |c|
        assert_equal(c.ord, r.readbyte)
      end
      assert_raise(EOFError) { r.readbyte }
    end)
  end

  def test_readchar
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      (%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"]).each do |c|
        assert_equal(c, r.readchar)
      end
      assert_raise(EOFError) { r.readchar }
    end)
  end

  def test_close_on_exec
    skip "IO\#close_on_exec is not implemented." unless have_close_on_exec?
    ruby do |f|
      assert_equal(false, f.close_on_exec?)
      f.close_on_exec = true
      assert_equal(true, f.close_on_exec?)
      f.close_on_exec = false
      assert_equal(false, f.close_on_exec?)
    end

    with_pipe do |r, w|
      assert_equal(false, r.close_on_exec?)
      r.close_on_exec = true
      assert_equal(true, r.close_on_exec?)
      r.close_on_exec = false
      assert_equal(false, r.close_on_exec?)

      assert_equal(false, w.close_on_exec?)
      w.close_on_exec = true
      assert_equal(true, w.close_on_exec?)
      w.close_on_exec = false
      assert_equal(false, w.close_on_exec?)
    end
  end

  def test_close_security_error
    with_pipe do |r, w|
      assert_raise(SecurityError) do
        safe_4 { r.close }
      end
    end
  end

  def test_pos
    t = make_tempfile

    open(t.path, IO::RDWR|IO::CREAT|IO::TRUNC, 0600) do |f|
      f.write "Hello"
      assert_equal(5, f.pos)
    end
    open(t.path, IO::RDWR|IO::CREAT|IO::TRUNC, 0600) do |f|
      f.sync = true
      f.read
      f.write "Hello"
      assert_equal(5, f.pos)
    end
  end

  def test_sysseek
    t = make_tempfile

    open(t.path) do |f|
      f.sysseek(-4, IO::SEEK_END)
      assert_equal("baz\n", f.read)
    end

    open(t.path) do |f|
      a = [f.getc, f.getc, f.getc]
      a.reverse_each {|c| f.ungetc c }
      assert_raise(IOError) { f.sysseek(1) }
    end
  end

  def test_syswrite
    t = make_tempfile

    open(t.path, "w") do |f|
      o = Object.new
      def o.to_s; "FOO\n"; end
      f.syswrite(o)
    end
    assert_equal("FOO\n", File.read(t.path))
  end

  def test_sysread
    t = make_tempfile

    open(t.path) do |f|
      a = [f.getc, f.getc, f.getc]
      a.reverse_each {|c| f.ungetc c }
      assert_raise(IOError) { f.sysread(1) }
    end
  end

  def test_flag
    t = make_tempfile

    assert_raise(ArgumentError) do
      open(t.path, "z") { }
    end

    assert_raise(ArgumentError) do
      open(t.path, "rr") { }
    end
  end

  def test_sysopen
    t = make_tempfile

    fd = IO.sysopen(t.path)
    assert_kind_of(Integer, fd)
    f = IO.for_fd(fd)
    assert_equal("foo\nbar\nbaz\n", f.read)
    f.close

    fd = IO.sysopen(t.path, "w", 0666)
    assert_kind_of(Integer, fd)
    if defined?(Fcntl::F_GETFL)
      f = IO.for_fd(fd)
    else
      f = IO.for_fd(fd, 0666)
    end
    f.write("FOO\n")
    f.close

    fd = IO.sysopen(t.path, "r")
    assert_kind_of(Integer, fd)
    f = IO.for_fd(fd)
    assert_equal("FOO\n", f.read)
    f.close
  end

  def try_fdopen(fd, autoclose = true, level = 100)
    if level > 0
      try_fdopen(fd, autoclose, level - 1)
      GC.start
      level
    else
      IO.for_fd(fd, autoclose: autoclose)
      nil
    end
  end

  def test_autoclose
    feature2250 = '[ruby-core:26222]'
    pre = 'ft2250'

    Tempfile.new(pre) do |t|
      f = IO.for_fd(t.fileno)
      assert_equal(true, f.autoclose?)
      f.autoclose = false
      assert_equal(false, f.autoclose?)
      f.close
      assert_nothing_raised(Errno::EBADF) {t.close}

      t.open
      f = IO.for_fd(t.fileno, autoclose: false)
      assert_equal(false, f.autoclose?)
      f.autoclose = true
      assert_equal(true, f.autoclose?)
      f.close
      assert_raise(Errno::EBADF) {t.close}
    end

    Tempfile.new(pre) do |t|
      try_fdopen(t.fileno)
      assert_raise(Errno::EBADF) {t.close}
    end

    Tempfile.new(pre) do |t|
      try_fdopen(f.fileno, false)
      assert_nothing_raised(Errno::EBADF) {t.close}
    end
  end

  def test_open_redirect
    o = Object.new
    def o.to_open; self; end
    assert_equal(o, open(o))
    o2 = nil
    open(o) do |f|
      o2 = f
    end
    assert_equal(o, o2)
  end

  def test_open_pipe
    open("|" + EnvUtil.rubybin, "r+") do |f|
      f.puts "puts 'foo'"
      f.close_write
      assert_equal("foo\n", f.read)
    end
  end

  def test_reopen
    t = make_tempfile

    with_pipe do |r, w|
      assert_raise(SecurityError) do
        safe_4 { r.reopen(t.path) }
      end
    end

    open(__FILE__) do |f|
      f.gets
      assert_nothing_raised {
        f.reopen(t.path)
        assert_equal("foo\n", f.gets)
      }
    end

    open(__FILE__) do |f|
      f.gets
      f2 = open(t.path)
      f2.gets
      assert_nothing_raised {
        f.reopen(f2)
        assert_equal("bar\n", f.gets, '[ruby-core:24240]')
      }
    end

    open(__FILE__) do |f|
      f2 = open(t.path)
      f.reopen(f2)
      assert_equal("foo\n", f.gets)
      assert_equal("bar\n", f.gets)
      f.reopen(f2)
      assert_equal("baz\n", f.gets, '[ruby-dev:39479]')
    end
  end

  def test_reopen_inherit
    mkcdtmpdir {
      system(EnvUtil.rubybin, '-e', <<"End")
        f = open("out", "w")
        STDOUT.reopen(f)
        STDERR.reopen(f)
        system(#{EnvUtil.rubybin.dump}, '-e', 'STDOUT.print "out"')
        system(#{EnvUtil.rubybin.dump}, '-e', 'STDERR.print "err"')
End
      assert_equal("outerr", File.read("out"))
    }
  end

  def test_foreach
    a = []
    IO.foreach("|" + EnvUtil.rubybin + " -e 'puts :foo; puts :bar; puts :baz'") {|x| a << x }
    assert_equal(["foo\n", "bar\n", "baz\n"], a)

    t = make_tempfile

    a = []
    IO.foreach(t.path) {|x| a << x }
    assert_equal(["foo\n", "bar\n", "baz\n"], a)

    a = []
    IO.foreach(t.path, {:mode => "r" }) {|x| a << x }
    assert_equal(["foo\n", "bar\n", "baz\n"], a)

    a = []
    IO.foreach(t.path, {:open_args => [] }) {|x| a << x }
    assert_equal(["foo\n", "bar\n", "baz\n"], a)

    a = []
    IO.foreach(t.path, {:open_args => ["r"] }) {|x| a << x }
    assert_equal(["foo\n", "bar\n", "baz\n"], a)

    a = []
    IO.foreach(t.path, "b") {|x| a << x }
    assert_equal(["foo\nb", "ar\nb", "az\n"], a)

    a = []
    IO.foreach(t.path, 3) {|x| a << x }
    assert_equal(["foo", "\n", "bar", "\n", "baz", "\n"], a)

    a = []
    IO.foreach(t.path, "b", 3) {|x| a << x }
    assert_equal(["foo", "\nb", "ar\n", "b", "az\n"], a)

  end

  def test_s_readlines
    t = make_tempfile

    assert_equal(["foo\n", "bar\n", "baz\n"], IO.readlines(t.path))
    assert_equal(["foo\nb", "ar\nb", "az\n"], IO.readlines(t.path, "b"))
    assert_equal(["fo", "o\n", "ba", "r\n", "ba", "z\n"], IO.readlines(t.path, 2))
    assert_equal(["fo", "o\n", "b", "ar", "\nb", "az", "\n"], IO.readlines(t.path, "b", 2))
  end

  def test_printf
    pipe(proc do |w|
      printf(w, "foo %s baz\n", "bar")
      w.close_write
    end, proc do |r|
      assert_equal("foo bar baz\n", r.read)
    end)
  end

  def test_print
    t = make_tempfile

    assert_in_out_err(["-", t.path], "print while $<.gets", %w(foo bar baz), [])
  end

  def test_print_separators
    $, = ':'
    $\ = "\n"
    pipe(proc do |w|
      w.print('a')
      w.print('a','b','c')
      w.close
    end, proc do |r|
      assert_equal("a\n", r.gets)
      assert_equal("a:b:c\n", r.gets)
      assert_nil r.gets
      r.close
    end)
  ensure
    $, = nil
    $\ = nil
  end

  def test_putc
    pipe(proc do |w|
      w.putc "A"
      w.putc "BC"
      w.putc 68
      w.close_write
    end, proc do |r|
      assert_equal("ABD", r.read)
    end)

    assert_in_out_err([], "putc 65", %w(A), [])
  end

  def test_puts_recursive_array
    a = ["foo"]
    a << a
    pipe(proc do |w|
      w.puts a
      w.close
    end, proc do |r|
      assert_equal("foo\n[...]\n", r.read)
    end)
  end

  def test_display
    pipe(proc do |w|
      "foo".display(w)
      w.close
    end, proc do |r|
      assert_equal("foo", r.read)
    end)

    assert_in_out_err([], "'foo'.display", %w(foo), [])
  end

  def test_set_stdout
    assert_raise(TypeError) { $> = Object.new }

    assert_in_out_err([], "$> = $stderr\nputs 'foo'", [], %w(foo))
  end

  def test_initialize
    return unless defined?(Fcntl::F_GETFL)

    t = make_tempfile

    fd = IO.sysopen(t.path, "w")
    assert_kind_of(Integer, fd)
    %w[r r+ w+ a+].each do |mode|
      assert_raise(Errno::EINVAL, "#{mode} [ruby-dev:38571]") {IO.new(fd, mode)}
    end
    f = IO.new(fd, "w")
    f.write("FOO\n")
    f.close

    assert_equal("FOO\n", File.read(t.path))
  end

  def test_reinitialize
    t = make_tempfile
    f = open(t.path)
    assert_raise(RuntimeError) do
      f.instance_eval { initialize }
    end
  end

  def test_new_with_block
    assert_in_out_err([], "r, w = IO.pipe; IO.new(r) {}", [], /^.+$/)
  end

  def test_readline2
    assert_in_out_err(["-e", <<-SRC], "foo\nbar\nbaz\n", %w(foo bar baz end), [])
      puts readline
      puts readline
      puts readline
      begin
        puts readline
      rescue EOFError
        puts "end"
      end
    SRC
  end

  def test_readlines
    assert_in_out_err(["-e", "p readlines"], "foo\nbar\nbaz\n",
                      ["[\"foo\\n\", \"bar\\n\", \"baz\\n\"]"], [])
  end

  def test_s_read
    t = make_tempfile

    assert_equal("foo\nbar\nbaz\n", File.read(t.path))
    assert_equal("foo\nba", File.read(t.path, 6))
    assert_equal("bar\n", File.read(t.path, 4, 4))
  end

  def test_uninitialized
    assert_raise(IOError) { IO.allocate.print "" }
  end

  def test_nofollow
    # O_NOFOLLOW is not standard.
    return if /freebsd|linux/ !~ RUBY_PLATFORM
    return unless defined? File::NOFOLLOW
    mkcdtmpdir {
      open("file", "w") {|f| f << "content" }
      begin
        File.symlink("file", "slnk")
      rescue NotImplementedError
        return
      end
      assert_raise(Errno::EMLINK, Errno::ELOOP) {
        open("slnk", File::RDONLY|File::NOFOLLOW) {}
      }
      assert_raise(Errno::EMLINK, Errno::ELOOP) {
        File.foreach("slnk", :open_args=>[File::RDONLY|File::NOFOLLOW]) {}
      }
    }
  end

  def test_tainted
    t = make_tempfile
    assert(File.read(t.path, 4).tainted?, '[ruby-dev:38826]')
    assert(File.open(t.path) {|f| f.read(4)}.tainted?, '[ruby-dev:38826]')
  end

  def test_binmode_after_closed
    t = make_tempfile
    t.close
    assert_raise(IOError) {t.binmode}
  end

  def test_threaded_flush
    bug3585 = '[ruby-core:31348]'
    src = %q{\
      t = Thread.new { sleep 3 }
      Thread.new {sleep 1; t.kill; p 'hi!'}
      t.join
    }.gsub(/^\s+/, '')
    10.times.map do
      Thread.start do
        assert_in_out_err([], src) {|stdout, stderr|
          assert_no_match(/hi.*hi/, stderr.join)
        }
      end
    end.each {|th| th.join}
  end

  def test_flush_in_finalizer1
    require 'tempfile'
    bug3910 = '[ruby-dev:42341]'
    path = Tempfile.new("bug3910").path
    fds = []
    assert_nothing_raised(TypeError, bug3910) do
      500.times {
        f = File.open(path, "w")
        fds << f.fileno
        f.print "hoge"
      }
    end
  ensure
    fds.each {|fd| IO.for_fd(fd).close rescue next}
  end

  def test_flush_in_finalizer2
    require 'tempfile'
    bug3910 = '[ruby-dev:42341]'
    path = Tempfile.new("bug3910").path
    1.times do
      io = open(path,"w")
      io.print "hoge"
    end
    assert_nothing_raised(TypeError, bug3910) do
      GC.start
    end
  end
end
