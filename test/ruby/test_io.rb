require 'test/unit'
require 'tmpdir'
require 'io/nonblock'
require 'socket'
require 'stringio'

class TestIO < Test::Unit::TestCase
  def test_gets_rs
    # default_rs
    r, w = IO.pipe
    w.print "aaa\nbbb\n"
    w.close
    assert_equal "aaa\n", r.gets
    assert_equal "bbb\n", r.gets
    assert_nil r.gets
    r.close

    # nil
    r, w = IO.pipe
    w.print "a\n\nb\n\n"
    w.close
    assert_equal "a\n\nb\n\n", r.gets(nil)
    assert_nil r.gets("")
    r.close

    # "\377"
    r, w = IO.pipe('ascii-8bit')
    w.print "\377xyz"
    w.close
    r.binmode
    assert_equal("\377", r.gets("\377"), "[ruby-dev:24460]")
    r.close

    # ""
    r, w = IO.pipe
    w.print "a\n\nb\n\n"
    w.close
    assert_equal "a\n\n", r.gets(""), "[ruby-core:03771]"
    assert_equal "b\n\n", r.gets("")
    assert_nil r.gets("")
    r.close
  end

  # This test cause SEGV.
  def test_ungetc
    r, w = IO.pipe
    w.close
    assert_raise(IOError, "[ruby-dev:31650]") { 20000.times { r.ungetc "a" } }
  ensure
    r.close
  end

  def test_each_byte
    r, w = IO.pipe
    w << "abc def"
    w.close
    r.each_byte {|byte| break if byte == 32 }
    assert_equal("def", r.read, "[ruby-dev:31659]")
  ensure
    r.close
  end

  def test_rubydev33072
    assert_raise(Errno::ENOENT, "[ruby-dev:33072]") do
      File.read("empty", nil, nil, {})
    end
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
    r, w = IO.pipe
    w << content
    w.close
    begin
      yield r
    ensure
      r.close
    end
  end

  def mkcdtmpdir
    Dir.mktmpdir {|d|
      Dir.chdir(d) {
        yield
      }
    }
  end

  def test_copy_stream
    mkcdtmpdir {|d|

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

      with_pipe {|r, w|
        ret = IO.copy_stream("src", w)
        assert_equal(content.bytesize, ret)
        w.close
        assert_equal(content, r.read)
      }

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
        with_pipe {|r2, w2|
          w2.sync = false
          w2 << "def"
          ret = IO.copy_stream(r1, w2)
          assert_equal(2, ret)
          w2.close
          assert_equal("defbc", r2.read)
        }
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        with_pipe {|r2, w2|
          w2.sync = false
          w2 << "def"
          ret = IO.copy_stream(r1, w2, 1)
          assert_equal(1, ret)
          w2.close
          assert_equal("defb", r2.read)
        }
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        with_pipe {|r2, w2|
          ret = IO.copy_stream(r1, w2)
          assert_equal(2, ret)
          w2.close
          assert_equal("bc", r2.read)
        }
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        with_pipe {|r2, w2|
          ret = IO.copy_stream(r1, w2, 1)
          assert_equal(1, ret)
          w2.close
          assert_equal("b", r2.read)
        }
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        with_pipe {|r2, w2|
          ret = IO.copy_stream(r1, w2, 0)
          assert_equal(0, ret)
          w2.close
          assert_equal("", r2.read)
        }
      }

      with_pipe {|r1, w1|
        w1 << "abc"
        assert_equal("a", r1.getc)
        with_pipe {|r2, w2|
          w1 << "def"
          w1.close
          ret = IO.copy_stream(r1, w2)
          assert_equal(5, ret)
          w2.close
          assert_equal("bcdef", r2.read)
        }
      }

      with_pipe {|r, w|
        ret = IO.copy_stream("src", w, 1, 1)
        assert_equal(1, ret)
        w.close
        assert_equal(content[1,1], r.read)
      }

      with_read_pipe("abc") {|r1|
        assert_equal("a", r1.getc)
        with_pipe {|r2, w2|
          w2.nonblock = true
          s = w2.syswrite("a" * 100000)
          t = Thread.new { sleep 0.1; r2.read }
          ret = IO.copy_stream(r1, w2)
          w2.close
          assert_equal(2, ret)
          assert_equal("a" * s + "bc", t.value)
        }
      }

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
        assert_equal(0, f.pos)
        ret = IO.copy_stream(f, "bigdst", nil, 10)
        assert_equal(bigcontent.bytesize-10, ret)
        assert_equal(bigcontent[10..-1], File.read("bigdst"))
        assert_equal(0, f.pos)
        ret = IO.copy_stream(f, "bigdst", 40, 30)
        assert_equal(40, ret)
        assert_equal(bigcontent[30, 40], File.read("bigdst"))
        assert_equal(0, f.pos)
      }

      with_pipe {|r, w|
        w.close
        assert_raise(IOError) { IO.copy_stream("src", w) }
      }

      megacontent = "abc" * 1234567
      File.open("megasrc", "w") {|f| f << megacontent }

      with_pipe {|r1, w1|
        with_pipe {|r2, w2|
          t1 = Thread.new { w1 << megacontent; w1.close }
          t2 = Thread.new { r2.read }
          r1.nonblock = true
          w2.nonblock = true
          ret = IO.copy_stream(r1, w2)
          assert_equal(megacontent.bytesize, ret)
          w2.close
          t1.join
          assert_equal(megacontent, t2.value)
        }
      }

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
    mkcdtmpdir {|d|
      with_pipe {|r, w|
        File.open("foo", "w") {|f| f << "abcd" }
        File.open("foo") {|f|
          f.read(1)
          assert_equal(3, IO.copy_stream(f, w, 10, 1))
        }
        w.close
        assert_equal("bcd", r.read)
      }
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
    mkcdtmpdir {|d|

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

      with_socketpair {|s1, s2|
        t = Thread.new { s2.read }
        s1.nonblock = true
        ret = IO.copy_stream("megasrc", s1)
        assert_equal(megacontent.bytesize, ret)
        s1.close
        result = t.value
        assert_equal(megacontent, result)
      }
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
    mkcdtmpdir {|d|
      File.open("foo", "w") {|f| f << "abcd" }
      src = "foo"
      dst = StringIO.new
      ret = IO.copy_stream(src, dst, 3)
      assert_equal(3, ret)
      assert_equal("abc", dst.string)
    }
  end

  def test_copy_stream_strio_to_fname
    mkcdtmpdir {|d|
      # StringIO to filename
      src = StringIO.new("abcd")
      ret = IO.copy_stream(src, "fooo", 3)
      assert_equal(3, ret)
      assert_equal("abc", File.read("fooo"))
      assert_equal(3, src.pos)
    }
  end

  def test_copy_stream_io_to_strio
    mkcdtmpdir {|d|
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
    mkcdtmpdir {|d|
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
    with_pipe {|r, w|
      w << "abcd"
      w.close
      assert_equal("a", r.read(1))
      sio = StringIO.new
      IO.copy_stream(r, sio)
      assert_equal("bcd", sio.string)
    }
  end

  def test_copy_stream_src_wbuf
    mkcdtmpdir {|d|
      with_pipe {|r, w|
        File.open("foe", "w+") {|f|
          f.write "abcd\n"
          f.rewind
          f.write "xy"
          IO.copy_stream(f, w)
        }
        assert_equal("xycd\n", File.read("foe"))
        w.close
        assert_equal("cd\n", r.read)
        r.close
      }
    }
  end

  def test_copy_stream_dst_rbuf
    mkcdtmpdir {|d|
      with_pipe {|r, w|
        w << "xyz"
        w.close
        File.open("fom", "w+") {|f|
          f.write "abcd\n"
          f.rewind
          assert_equal("abc", f.read(3))
          f.ungetc "c"
          IO.copy_stream(r, f)
        }
        assert_equal("abxyz", File.read("fom"))
      }
    }
  end

end
