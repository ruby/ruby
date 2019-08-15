# coding: US-ASCII
# frozen_string_literal: false
require 'test/unit'
require 'tmpdir'
require "fcntl"
require 'io/nonblock'
require 'pathname'
require 'socket'
require 'stringio'
require 'timeout'
require 'tempfile'
require 'weakref'

class TestIO < Test::Unit::TestCase
  module Feature
    def have_close_on_exec?
      $stdin.close_on_exec?
      true
    rescue NotImplementedError
      false
    end

    def have_nonblock?
      IO.method_defined?("nonblock=")
    end
  end

  include Feature
  extend Feature

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
    w&.close
    r&.close
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
      r.close
      w.close
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

  def trapping_usr2
    @usr2_rcvd  = 0
    r, w = IO.pipe
    trap(:USR2) do
      w.write([@usr2_rcvd += 1].pack('L'))
    end
    yield r
  ensure
    trap(:USR2, "DEFAULT")
    w&.close
    r&.close
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

  def test_binmode_pipe
    EnvUtil.with_default_internal(Encoding::UTF_8) do
      EnvUtil.with_default_external(Encoding::UTF_8) do
        begin
          reader0, writer0 = IO.pipe
          reader0.binmode
          writer0.binmode

          reader1, writer1 = IO.pipe

          reader2, writer2 = IO.pipe(binmode: true)
          assert_predicate writer0, :binmode?
          assert_predicate writer2, :binmode?
          assert_equal writer0.binmode?, writer2.binmode?
          assert_equal writer0.external_encoding, writer2.external_encoding
          assert_equal writer0.internal_encoding, writer2.internal_encoding
          assert_predicate reader0, :binmode?
          assert_predicate reader2, :binmode?
          assert_equal reader0.binmode?, reader2.binmode?
          assert_equal reader0.external_encoding, reader2.external_encoding
          assert_equal reader0.internal_encoding, reader2.internal_encoding

          reader3, writer3 = IO.pipe("UTF-8:UTF-8", binmode: true)
          assert_predicate writer3, :binmode?
          assert_equal writer1.external_encoding, writer3.external_encoding
          assert_equal writer1.internal_encoding, writer3.internal_encoding
          assert_predicate reader3, :binmode?
          assert_equal reader1.external_encoding, reader3.external_encoding
          assert_equal reader1.internal_encoding, reader3.internal_encoding

          reader4, writer4 = IO.pipe("UTF-8:UTF-8", binmode: true)
          assert_predicate writer4, :binmode?
          assert_equal writer1.external_encoding, writer4.external_encoding
          assert_equal writer1.internal_encoding, writer4.internal_encoding
          assert_predicate reader4, :binmode?
          assert_equal reader1.external_encoding, reader4.external_encoding
          assert_equal reader1.internal_encoding, reader4.internal_encoding

          reader5, writer5 = IO.pipe("UTF-8", "UTF-8", binmode: true)
          assert_predicate writer5, :binmode?
          assert_equal writer1.external_encoding, writer5.external_encoding
          assert_equal writer1.internal_encoding, writer5.internal_encoding
          assert_predicate reader5, :binmode?
          assert_equal reader1.external_encoding, reader5.external_encoding
          assert_equal reader1.internal_encoding, reader5.internal_encoding
        ensure
          [
            reader0, writer0,
            reader1, writer1,
            reader2, writer2,
            reader3, writer3,
            reader4, writer4,
            reader5, writer5,
          ].compact.map(&:close)
        end
      end
    end
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
      assert_not_predicate(r, :closed?)
      assert_predicate(w, :closed?)
      :foooo
    }
    assert_equal(:foooo, ret)
    assert_predicate(x[0], :closed?)
    assert_predicate(x[1], :closed?)
  end

  def test_pipe_block_close
    4.times {|i|
      x = nil
      IO.pipe {|r, w|
        x = [r,w]
        r.close if (i&1) == 0
        w.close if (i&2) == 0
      }
      assert_predicate(x[0], :closed?)
      assert_predicate(x[1], :closed?)
    }
  end

  def test_gets_rs
    rs = ":"
    pipe(proc do |w|
      w.print "aaa:bbb"
      w.close
    end, proc do |r|
      assert_equal "aaa:", r.gets(rs)
      assert_equal "bbb", r.gets(rs)
      assert_nil r.gets(rs)
      r.close
    end)
  end

  def test_gets_default_rs
    pipe(proc do |w|
      w.print "aaa\nbbb\n"
      w.close
    end, proc do |r|
      assert_equal "aaa\n", r.gets
      assert_equal "bbb\n", r.gets
      assert_nil r.gets
      r.close
    end)
  end

  def test_gets_rs_nil
    pipe(proc do |w|
      w.print "a\n\nb\n\n"
      w.close
    end, proc do |r|
      assert_equal "a\n\nb\n\n", r.gets(nil)
      assert_nil r.gets("")
      r.close
    end)
  end

  def test_gets_rs_377
    pipe(proc do |w|
      w.print "\377xyz"
      w.close
    end, proc do |r|
      r.binmode
      assert_equal("\377", r.gets("\377"), "[ruby-dev:24460]")
      r.close
    end)
  end

  def test_gets_paragraph
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

  def test_gets_chomp_rs
    rs = ":"
    pipe(proc do |w|
      w.print "aaa:bbb"
      w.close
    end, proc do |r|
      assert_equal "aaa", r.gets(rs, chomp: true)
      assert_equal "bbb", r.gets(rs, chomp: true)
      assert_nil r.gets(rs, chomp: true)
      r.close
    end)
  end

  def test_gets_chomp_default_rs
    pipe(proc do |w|
      w.print "aaa\r\nbbb\nccc"
      w.close
    end, proc do |r|
      assert_equal "aaa", r.gets(chomp: true)
      assert_equal "bbb", r.gets(chomp: true)
      assert_equal "ccc", r.gets(chomp: true)
      assert_nil r.gets
      r.close
    end)

    (0..3).each do |i|
      pipe(proc do |w|
        w.write("a" * ((4096 << i) - 4), "\r\n" "a\r\n")
        w.close
      end,
      proc do |r|
        r.gets
        assert_equal "a", r.gets(chomp: true)
        assert_nil r.gets
        r.close
      end)
    end
  end

  def test_gets_chomp_rs_nil
    pipe(proc do |w|
      w.print "a\n\nb\n\n"
      w.close
    end, proc do |r|
      assert_equal "a\n\nb\n", r.gets(nil, chomp: true)
      assert_nil r.gets("")
      r.close
    end)
  end

  def test_gets_chomp_paragraph
    pipe(proc do |w|
      w.print "a\n\nb\n\n"
      w.close
    end, proc do |r|
      assert_equal "a", r.gets("", chomp: true)
      assert_equal "b", r.gets("", chomp: true)
      assert_nil r.gets("", chomp: true)
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
    make_tempfile {|t|
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
    }
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

  def test_each_byte_with_seek
    make_tempfile {|t|
      bug5119 = '[ruby-core:38609]'
      i = 0
      open(t.path) do |f|
        f.each_byte {i = f.pos}
      end
      assert_equal(12, i, bug5119)
    }
  end

  def test_each_codepoint
    make_tempfile {|t|
      bug2959 = '[ruby-core:28650]'
      a = ""
      File.open(t, 'rt') {|f|
        f.each_codepoint {|c| a << c}
      }
      assert_equal("foo\nbar\nbaz\n", a, bug2959)
    }
  end

  def test_codepoints
    make_tempfile {|t|
      bug2959 = '[ruby-core:28650]'
      a = ""
      File.open(t, 'rt') {|f|
        assert_warn(/deprecated/) {
          f.codepoints {|c| a << c}
        }
      }
      assert_equal("foo\nbar\nbaz\n", a, bug2959)
    }
  end

  def test_rubydev33072
    t = make_tempfile
    path = t.path
    t.close!
    assert_raise(Errno::ENOENT, "[ruby-dev:33072]") do
      File.read(path, nil, nil, {})
    end
  end

  def with_srccontent(content = "baz")
    src = "src"
    mkcdtmpdir {
      File.open(src, "w") {|f| f << content }
      yield src, content
    }
  end

  def test_copy_stream_small
    with_srccontent("foobar") {|src, content|
      ret = IO.copy_stream(src, "dst")
      assert_equal(content.bytesize, ret)
      assert_equal(content, File.read("dst"))
    }
  end

  def test_copy_stream_append
    with_srccontent("foobar") {|src, content|
      File.open('dst', 'ab') do |dst|
        ret = IO.copy_stream(src, dst)
        assert_equal(content.bytesize, ret)
        assert_equal(content, File.read("dst"))
      end
    }
  end

  def test_copy_stream_smaller
    with_srccontent {|src, content|

      # overwrite by smaller file.
      dst = "dst"
      File.open(dst, "w") {|f| f << "foobar"}

      ret = IO.copy_stream(src, dst)
      assert_equal(content.bytesize, ret)
      assert_equal(content, File.read(dst))

      ret = IO.copy_stream(src, dst, 2)
      assert_equal(2, ret)
      assert_equal(content[0,2], File.read(dst))

      ret = IO.copy_stream(src, dst, 0)
      assert_equal(0, ret)
      assert_equal("", File.read(dst))

      ret = IO.copy_stream(src, dst, nil, 1)
      assert_equal(content.bytesize-1, ret)
      assert_equal(content[1..-1], File.read(dst))
    }
  end

  def test_copy_stream_noent
    with_srccontent {|src, content|
      assert_raise(Errno::ENOENT) {
        IO.copy_stream("nodir/foo", "dst")
      }

      assert_raise(Errno::ENOENT) {
        IO.copy_stream(src, "nodir/bar")
      }
    }
  end

  def test_copy_stream_pipe
    with_srccontent {|src, content|
      pipe(proc do |w|
        ret = IO.copy_stream(src, w)
        assert_equal(content.bytesize, ret)
        w.close
      end, proc do |r|
        assert_equal(content, r.read)
      end)
    }
  end

  def test_copy_stream_write_pipe
    with_srccontent {|src, content|
      with_pipe {|r, w|
        w.close
        assert_raise(IOError) { IO.copy_stream(src, w) }
      }
    }
  end

  def with_pipecontent
    mkcdtmpdir {
      yield "abc"
    }
  end

  def test_copy_stream_pipe_to_file
    with_pipecontent {|pipe_content|
      dst = "dst"
      with_read_pipe(pipe_content) {|r|
        ret = IO.copy_stream(r, dst)
        assert_equal(pipe_content.bytesize, ret)
        assert_equal(pipe_content, File.read(dst))
      }
    }
  end

  def test_copy_stream_read_pipe
    with_pipecontent {|pipe_content|
      with_read_pipe(pipe_content) {|r1|
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

      with_read_pipe(pipe_content) {|r1|
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

      with_read_pipe(pipe_content) {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          ret = IO.copy_stream(r1, w2)
          assert_equal(2, ret)
          w2.close
        end, proc do |r2|
          assert_equal("bc", r2.read)
        end)
      }

      with_read_pipe(pipe_content) {|r1|
        assert_equal("a", r1.getc)
        pipe(proc do |w2|
          ret = IO.copy_stream(r1, w2, 1)
          assert_equal(1, ret)
          w2.close
        end, proc do |r2|
          assert_equal("b", r2.read)
        end)
      }

      with_read_pipe(pipe_content) {|r1|
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
    }
  end

  def test_copy_stream_file_to_pipe
    with_srccontent {|src, content|
      pipe(proc do |w|
        ret = IO.copy_stream(src, w, 1, 1)
        assert_equal(1, ret)
        w.close
      end, proc do |r|
        assert_equal(content[1,1], r.read)
      end)
    }
  end

  if have_nonblock?
    def test_copy_stream_no_busy_wait
      skip "MJIT has busy wait on GC. This sometimes fails with --jit." if RubyVM::MJIT.enabled?
      skip "multiple threads already active" if Thread.list.size > 1

      msg = 'r58534 [ruby-core:80969] [Backport #13533]'
      IO.pipe do |r,w|
        r.nonblock = true
        assert_cpu_usage_low(msg, stop: ->{w.close}) do
          IO.copy_stream(r, IO::NULL)
        end
      end
    end

    def test_copy_stream_pipe_nonblock
      mkcdtmpdir {
        with_read_pipe("abc") {|r1|
          assert_equal("a", r1.getc)
          with_pipe {|r2, w2|
            begin
              w2.nonblock = true
            rescue Errno::EBADF
              skip "nonblocking IO for pipe is not implemented"
            end
            s = w2.syswrite("a" * 100000)
            t = Thread.new { sleep 0.1; r2.read }
            ret = IO.copy_stream(r1, w2)
            w2.close
            assert_equal(2, ret)
            assert_equal("a" * s + "bc", t.value)
          }
        }
      }
    end
  end

  def with_bigcontent
    yield "abc" * 123456
  end

  def with_bigsrc
    mkcdtmpdir {
      with_bigcontent {|bigcontent|
        bigsrc = "bigsrc"
        File.open("bigsrc", "w") {|f| f << bigcontent }
        yield bigsrc, bigcontent
      }
    }
  end

  def test_copy_stream_bigcontent
    with_bigsrc {|bigsrc, bigcontent|
      ret = IO.copy_stream(bigsrc, "bigdst")
      assert_equal(bigcontent.bytesize, ret)
      assert_equal(bigcontent, File.read("bigdst"))
    }
  end

  def test_copy_stream_bigcontent_chop
    with_bigsrc {|bigsrc, bigcontent|
      ret = IO.copy_stream(bigsrc, "bigdst", nil, 100)
      assert_equal(bigcontent.bytesize-100, ret)
      assert_equal(bigcontent[100..-1], File.read("bigdst"))
    }
  end

  def test_copy_stream_bigcontent_mid
    with_bigsrc {|bigsrc, bigcontent|
      ret = IO.copy_stream(bigsrc, "bigdst", 30000, 100)
      assert_equal(30000, ret)
      assert_equal(bigcontent[100, 30000], File.read("bigdst"))
    }
  end

  def test_copy_stream_bigcontent_fpos
    with_bigsrc {|bigsrc, bigcontent|
      File.open(bigsrc) {|f|
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
          #skip "pread(2) is not implemented."
        end
      }
    }
  end

  def test_copy_stream_closed_pipe
    with_srccontent {|src,|
      with_pipe {|r, w|
        w.close
        assert_raise(IOError) { IO.copy_stream(src, w) }
      }
    }
  end

  def with_megacontent
    yield "abc" * 1234567
  end

  def with_megasrc
    mkcdtmpdir {
      with_megacontent {|megacontent|
        megasrc = "megasrc"
        File.open(megasrc, "w") {|f| f << megacontent }
        yield megasrc, megacontent
      }
    }
  end

  if have_nonblock?
    def test_copy_stream_megacontent_nonblock
      with_megacontent {|megacontent|
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
            t3 = Thread.new {
              ret = IO.copy_stream(r1, w2)
              assert_equal(megacontent.bytesize, ret)
              w2.close
            }
            _, t2_value, _ = assert_join_threads([t1, t2, t3])
            assert_equal(megacontent, t2_value)
          }
        }
      }
    end
  end

  def test_copy_stream_megacontent_pipe_to_file
    with_megasrc {|megasrc, megacontent|
      with_pipe {|r1, w1|
        with_pipe {|r2, w2|
          t1 = Thread.new { w1 << megacontent; w1.close }
          t2 = Thread.new { r2.read }
          t3 = Thread.new {
            ret = IO.copy_stream(r1, w2)
            assert_equal(megacontent.bytesize, ret)
            w2.close
          }
          _, t2_value, _ = assert_join_threads([t1, t2, t3])
          assert_equal(megacontent, t2_value)
        }
      }
    }
  end

  def test_copy_stream_megacontent_file_to_pipe
    with_megasrc {|megasrc, megacontent|
      with_pipe {|r, w|
        t1 = Thread.new { r.read }
        t2 = Thread.new {
          ret = IO.copy_stream(megasrc, w)
          assert_equal(megacontent.bytesize, ret)
          w.close
        }
        t1_value, _ = assert_join_threads([t1, t2])
        assert_equal(megacontent, t1_value)
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

  def test_copy_stream_socket1
    with_srccontent("foobar") {|src, content|
      with_socketpair {|s1, s2|
        ret = IO.copy_stream(src, s1)
        assert_equal(content.bytesize, ret)
        s1.close
        assert_equal(content, s2.read)
      }
    }
  end if defined? UNIXSocket

  def test_copy_stream_socket2
    with_bigsrc {|bigsrc, bigcontent|
      with_socketpair {|s1, s2|
        t1 = Thread.new { s2.read }
        t2 = Thread.new {
          ret = IO.copy_stream(bigsrc, s1)
          assert_equal(bigcontent.bytesize, ret)
          s1.close
        }
        result, _ = assert_join_threads([t1, t2])
        assert_equal(bigcontent, result)
      }
    }
  end if defined? UNIXSocket

  def test_copy_stream_socket3
    with_bigsrc {|bigsrc, bigcontent|
      with_socketpair {|s1, s2|
        t1 = Thread.new { s2.read }
        t2 = Thread.new {
          ret = IO.copy_stream(bigsrc, s1, 10000)
          assert_equal(10000, ret)
          s1.close
        }
        result, _ = assert_join_threads([t1, t2])
        assert_equal(bigcontent[0,10000], result)
      }
    }
  end if defined? UNIXSocket

  def test_copy_stream_socket4
    with_bigsrc {|bigsrc, bigcontent|
      File.open(bigsrc) {|f|
        assert_equal(0, f.pos)
        with_socketpair {|s1, s2|
          t1 = Thread.new { s2.read }
          t2 = Thread.new {
            ret = IO.copy_stream(f, s1, nil, 100)
            assert_equal(bigcontent.bytesize-100, ret)
            assert_equal(0, f.pos)
            s1.close
          }
          result, _ = assert_join_threads([t1, t2])
          assert_equal(bigcontent[100..-1], result)
        }
      }
    }
  end if defined? UNIXSocket

  def test_copy_stream_socket5
    with_bigsrc {|bigsrc, bigcontent|
      File.open(bigsrc) {|f|
        assert_equal(bigcontent[0,100], f.read(100))
        assert_equal(100, f.pos)
        with_socketpair {|s1, s2|
          t1 = Thread.new { s2.read }
          t2 = Thread.new {
            ret = IO.copy_stream(f, s1)
            assert_equal(bigcontent.bytesize-100, ret)
            assert_equal(bigcontent.length, f.pos)
            s1.close
          }
          result, _ = assert_join_threads([t1, t2])
          assert_equal(bigcontent[100..-1], result)
        }
      }
    }
  end if defined? UNIXSocket

  def test_copy_stream_socket6
    mkcdtmpdir {
      megacontent = "abc" * 1234567
      File.open("megasrc", "w") {|f| f << megacontent }

      with_socketpair {|s1, s2|
        begin
          s1.nonblock = true
        rescue Errno::EBADF
          skip "nonblocking IO for pipe is not implemented"
        end
        t1 = Thread.new { s2.read }
        t2 = Thread.new {
          ret = IO.copy_stream("megasrc", s1)
          assert_equal(megacontent.bytesize, ret)
          s1.close
        }
        result, _ = assert_join_threads([t1, t2])
        assert_equal(megacontent, result)
      }
    }
  end if defined? UNIXSocket

  def test_copy_stream_socket7
    GC.start
    mkcdtmpdir {
      megacontent = "abc" * 1234567
      File.open("megasrc", "w") {|f| f << megacontent }

      with_socketpair {|s1, s2|
        begin
          s1.nonblock = true
        rescue Errno::EBADF
          skip "nonblocking IO for pipe is not implemented"
        end
        trapping_usr2 do |rd|
          nr = 30
          begin
            pid = fork do
              s1.close
              IO.select([s2])
              Process.kill(:USR2, Process.ppid)
              buf = String.new(capacity: 16384)
              nil while s2.read(16384, buf)
            end
            s2.close
            nr.times do
              assert_equal megacontent.bytesize, IO.copy_stream("megasrc", s1)
            end
            assert_equal(1, rd.read(4).unpack1('L'))
          ensure
            s1.close
            _, status = Process.waitpid2(pid) if pid
          end
          assert_predicate(status, :success?)
        end
      }
    }
  end if defined? UNIXSocket and IO.method_defined?("nonblock=")

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

  def test_copy_stream_strio_to_tempfile
    bug11015 = '[ruby-core:68676] [Bug #11015]'
    # StringIO to Tempfile
    src = StringIO.new("abcd")
    dst = Tempfile.new("baz")
    ret = IO.copy_stream(src, dst)
    assert_equal(4, ret)
    pos = dst.pos
    dst.rewind
    assert_equal("abcd", dst.read)
    assert_equal(4, pos, bug11015)
  ensure
    dst.close!
  end

  def test_copy_stream_pathname_to_pathname
    bug11199 = '[ruby-dev:49008] [Bug #11199]'
    mkcdtmpdir {
      File.open("src", "w") {|f| f << "ok" }
      src = Pathname.new("src")
      dst = Pathname.new("dst")
      IO.copy_stream(src, dst)
      assert_equal("ok", IO.read("dst"), bug11199)
    }
  end

  def test_copy_stream_write_in_binmode
    bug8767 = '[ruby-core:56518] [Bug #8767]'
    mkcdtmpdir {
      EnvUtil.with_default_internal(Encoding::UTF_8) do
        # StringIO to object with to_path
        bytes = "\xDE\xAD\xBE\xEF".force_encoding(Encoding::ASCII_8BIT)
        src = StringIO.new(bytes)
        dst = Object.new
        def dst.to_path
          "qux"
        end
        assert_nothing_raised(bug8767) {
          IO.copy_stream(src, dst)
        }
        assert_equal(bytes, File.binread("qux"), bug8767)
        assert_equal(4, src.pos, bug8767)
      end
    }
  end

  def test_copy_stream_read_in_binmode
    bug8767 = '[ruby-core:56518] [Bug #8767]'
    mkcdtmpdir {
      EnvUtil.with_default_internal(Encoding::UTF_8) do
        # StringIO to object with to_path
        bytes = "\xDE\xAD\xBE\xEF".force_encoding(Encoding::ASCII_8BIT)
        File.binwrite("qux", bytes)
        dst = StringIO.new
        src = Object.new
        def src.to_path
          "qux"
        end
        assert_nothing_raised(bug8767) {
          IO.copy_stream(src, dst)
        }
        assert_equal(bytes, dst.string.b, bug8767)
        assert_equal(4, dst.pos, bug8767)
      end
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
      t1 = Thread.new {
        w.close
      }
      t2 = Thread.new { r.read }
      _, result = assert_join_threads([t1, t2])
      assert_equal("zzabcd", result)
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

  class Bug5237
    attr_reader :count
    def initialize
      @count = 0
    end

    def read(bytes, buffer)
      @count += 1
      buffer.replace "this is a test"
      nil
    end
  end

  def test_copy_stream_broken_src_read_eof
    src = Bug5237.new
    dst = StringIO.new
    assert_equal 0, src.count
    th = Thread.new { IO.copy_stream(src, dst) }
    flunk("timeout") unless th.join(10)
    assert_equal 1, src.count
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

  def test_copy_stream_to_duplex_io
    result = IO.pipe {|a,w|
      th = Thread.start {w.puts "yes"; w.close}
      IO.popen([EnvUtil.rubybin, '-pe$_="#$.:#$_"'], "r+") {|b|
        IO.copy_stream(a, b)
        b.close_write
        assert_join_threads([th])
        b.read
      }
    }
    assert_equal("1:yes\n", result)
  end

  def ruby(*args)
    args = ['-e', '$>.write($<.read)'] if args.empty?
    ruby = EnvUtil.rubybin
    opts = {}
    if defined?(Process::RLIMIT_NPROC)
      lim = Process.getrlimit(Process::RLIMIT_NPROC)[1]
      opts[:rlimit_nproc] = [lim, 2048].min
    end
    f = IO.popen([ruby] + args, 'r+', opts)
    pid = f.pid
    yield(f)
  ensure
    f.close unless !f || f.closed?
    begin
      Process.wait(pid)
    rescue Errno::ECHILD, Errno::ESRCH
    end
  end

  def test_try_convert
    assert_equal(STDOUT, IO.try_convert(STDOUT))
    assert_equal(nil, IO.try_convert("STDOUT"))
  end

  def test_ungetc2
    f = false
    pipe(proc do |w|
      Thread.pass until f
      w.write("1" * 10000)
      w.close
    end, proc do |r|
      r.ungetc("0" * 10000)
      f = true
      assert_equal("0" * 10000 + "1" * 10000, r.read)
    end)
  end

  def test_write_with_multiple_arguments
    pipe(proc do |w|
      w.write("foo", "bar")
      w.close
    end, proc do |r|
      assert_equal("foobar", r.read)
    end)
  end

  def test_write_with_multiple_arguments_and_buffer
    mkcdtmpdir do
      line = "x"*9+"\n"
      file = "test.out"
      open(file, "wb") do |w|
        w.write(line)
        assert_equal(11, w.write(line, "\n"))
      end
      open(file, "rb") do |r|
        assert_equal([line, line, "\n"], r.readlines)
      end

      line = "x"*99+"\n"
      open(file, "wb") do |w|
        w.write(line*81)        # 8100 bytes
        assert_equal(100, w.write("a"*99, "\n"))
      end
      open(file, "rb") do |r|
        81.times {assert_equal(line, r.gets)}
        assert_equal("a"*99+"\n", r.gets)
      end
    end
  end

  def test_write_with_many_arguments
    [1023, 1024].each do |n|
      pipe(proc do |w|
        w.write(*(["a"] * n))
        w.close
      end, proc do |r|
        assert_equal("a" * n, r.read)
      end)
    end
  end

  def test_write_with_multiple_nonstring_arguments
    assert_in_out_err([], "STDOUT.write(:foo, :bar)", ["foobar"])
  end

  def test_write_buffered_with_multiple_arguments
    out, err, (_, status) = EnvUtil.invoke_ruby(["-e", "sleep 0.1;puts 'foo'"], "", true, true) do |_, o, e, i|
      [o.read, e.read, Process.waitpid2(i)]
    end
    assert_predicate(status, :success?)
    assert_equal("foo\n", out)
    assert_empty(err)
  end

  def test_write_no_args
    IO.pipe do |r, w|
      assert_equal 0, w.write, '[ruby-core:86285] [Bug #14338]'
      assert_equal :wait_readable, r.read_nonblock(1, exception: false)
    end
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
      begin
        f2 = f.dup
        f.puts "foo"
        f2.puts "bar"
        f.close_write
        f2.close_write
        assert_equal("foo\nbar\n", f.read)
        assert_equal("", f2.read)
      ensure
        f2.close
      end
    end
  end

  def test_dup_many
    opts = {}
    opts[:rlimit_nofile] = 1024 if defined?(Process::RLIMIT_NOFILE)
    assert_separately([], <<-'End', opts)
      a = []
      assert_raise(Errno::EMFILE, Errno::ENFILE, Errno::ENOMEM) do
        loop {a << IO.pipe}
      end
      assert_raise(Errno::EMFILE, Errno::ENFILE, Errno::ENOMEM) do
        loop {a << [a[-1][0].dup, a[-1][1].dup]}
      end
    End
  end

  def test_inspect
    with_pipe do |r, w|
      assert_match(/^#<IO:fd \d+>$/, r.inspect)
      r.freeze
      assert_match(/^#<IO:fd \d+>$/, r.inspect)
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
      Thread.pass until t.stop?
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

  def test_readpartial_with_not_empty_buffer
    pipe(proc do |w|
      w.write "foob"
      w.close
    end, proc do |r|
      r.readpartial(5, s = "01234567")
      assert_equal("foob", s)
    end)
  end

  def test_readpartial_buffer_error
    with_pipe do |r, w|
      s = ""
      t = Thread.new { r.readpartial(5, s) }
      Thread.pass until t.stop?
      t.kill
      t.value
      assert_equal("", s)
    end
  end if /cygwin/ !~ RUBY_PLATFORM

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
      Thread.pass until t.stop?
      assert_raise(RuntimeError) { s.clear }
      w.write "foobarbaz"
      w.close
      assert_equal("fooba", t.value)
    end
  end

  def test_read_with_not_empty_buffer
    pipe(proc do |w|
      w.write "foob"
      w.close
    end, proc do |r|
      r.read(nil, s = "01234567")
      assert_equal("foob", s)
    end)
  end

  def test_read_buffer_error
    with_pipe do |r, w|
      s = ""
      t = Thread.new { r.read(5, s) }
      Thread.pass until t.stop?
      t.kill
      t.value
      assert_equal("", s)
    end
    with_pipe do |r, w|
      s = "xxx"
      t = Thread.new {r.read(2, s)}
      Thread.pass until t.stop?
      t.kill
      t.value
      assert_equal("xxx", s)
    end
  end if /cygwin/ !~ RUBY_PLATFORM

  def test_write_nonblock
    pipe(proc do |w|
      w.write_nonblock(1)
      w.close
    end, proc do |r|
      assert_equal("1", r.read)
    end)
  end

  def test_read_nonblock_with_not_empty_buffer
    with_pipe {|r, w|
      w.write "foob"
      w.close
      r.read_nonblock(5, s = "01234567")
      assert_equal("foob", s)
    }
  end

  def test_write_nonblock_simple_no_exceptions
    pipe(proc do |w|
      w.write_nonblock('1', exception: false)
      w.close
    end, proc do |r|
      assert_equal("1", r.read)
    end)
  end

  def test_read_nonblock_error
    with_pipe {|r, w|
      begin
        r.read_nonblock 4096
      rescue Errno::EWOULDBLOCK
        assert_kind_of(IO::WaitReadable, $!)
      end
    }

    with_pipe {|r, w|
      begin
        r.read_nonblock 4096, ""
      rescue Errno::EWOULDBLOCK
        assert_kind_of(IO::WaitReadable, $!)
      end
    }
  end if have_nonblock?

  def test_read_nonblock_invalid_exception
    with_pipe {|r, w|
      assert_raise(ArgumentError) {r.read_nonblock(4096, exception: 1)}
    }
  end if have_nonblock?

  def test_read_nonblock_no_exceptions
    skip '[ruby-core:90895] MJIT worker may leave fd open in a forked child' if RubyVM::MJIT.enabled? # TODO: consider acquiring GVL from MJIT worker.
    with_pipe {|r, w|
      assert_equal :wait_readable, r.read_nonblock(4096, exception: false)
      w.puts "HI!"
      assert_equal "HI!\n", r.read_nonblock(4096, exception: false)
      w.close
      assert_equal nil, r.read_nonblock(4096, exception: false)
    }
  end if have_nonblock?

  def test_read_nonblock_with_buffer_no_exceptions
    with_pipe {|r, w|
      assert_equal :wait_readable, r.read_nonblock(4096, "", exception: false)
      w.puts "HI!"
      buf = "buf"
      value = r.read_nonblock(4096, buf, exception: false)
      assert_equal value, "HI!\n"
      assert_same(buf, value)
      w.close
      assert_equal nil, r.read_nonblock(4096, "", exception: false)
    }
  end if have_nonblock?

  def test_write_nonblock_error
    with_pipe {|r, w|
      begin
        loop {
          w.write_nonblock "a"*100000
        }
      rescue Errno::EWOULDBLOCK
        assert_kind_of(IO::WaitWritable, $!)
      end
    }
  end if have_nonblock?

  def test_write_nonblock_invalid_exception
    with_pipe {|r, w|
      assert_raise(ArgumentError) {w.write_nonblock(4096, exception: 1)}
    }
  end if have_nonblock?

  def test_write_nonblock_no_exceptions
    with_pipe {|r, w|
      loop {
        ret = w.write_nonblock("a"*100000, exception: false)
        if ret.is_a?(Symbol)
          assert_equal :wait_writable, ret
          break
        end
      }
    }
  end if have_nonblock?

  def test_gets
    pipe(proc do |w|
      w.write "foobarbaz"
      w.close
    end, proc do |r|
      assert_equal("", r.gets(0))
      assert_equal("foobarbaz", r.gets(9))
    end)
  end

  def test_close_read
    ruby do |f|
      f.close_read
      f.write "foobarbaz"
      assert_raise(IOError) { f.read }
      assert_nothing_raised(IOError) {f.close_read}
      assert_nothing_raised(IOError) {f.close}
      assert_nothing_raised(IOError) {f.close_read}
    end
  end

  def test_close_read_pipe
    with_pipe do |r, w|
      r.close_read
      assert_raise(Errno::EPIPE) { w.write "foobarbaz" }
      assert_nothing_raised(IOError) {r.close_read}
      assert_nothing_raised(IOError) {r.close}
      assert_nothing_raised(IOError) {r.close_read}
    end
  end

  def test_write_epipe_nosync
    assert_separately([], <<-"end;")
      r, w = IO.pipe
      r.close
      w.sync = false
      assert_raise(Errno::EPIPE) {
        loop { w.write "a" }
      }
    end;
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
      assert_nothing_raised(IOError) {f.close_write}
      assert_nothing_raised(IOError) {f.close}
      assert_nothing_raised(IOError) {f.close_write}
    end
  end

  def test_close_write_non_readable
    with_pipe do |r, w|
      assert_raise(IOError) do
        r.close_write
      end
    end
  end

  def test_close_read_write_separately
    bug = '[ruby-list:49598]'
    (1..10).each do |i|
      assert_nothing_raised(IOError, "#{bug} trying ##{i}") do
        IO.popen(EnvUtil.rubybin, "r+") {|f|
          th = Thread.new {f.close_write}
          f.close_read
          th.join
        }
      end
    end
  end

  def test_pid
    IO.pipe {|r, w|
      assert_equal(nil, r.pid)
      assert_equal(nil, w.pid)
    }

    begin
      pipe = IO.popen(EnvUtil.rubybin, "r+")
      pid1 = pipe.pid
      pipe.puts "p $$"
      pipe.close_write
      pid2 = pipe.read.chomp.to_i
      assert_equal(pid2, pid1)
      assert_equal(pid2, pipe.pid)
    ensure
      pipe.close
    end
    assert_raise(IOError) { pipe.pid }
  end

  def test_pid_after_close_read
    pid1 = pid2 = nil
    IO.popen("exit ;", "r+") do |io|
      pid1 = io.pid
      io.close_read
      pid2 = io.pid
    end
    assert_not_nil(pid1)
    assert_equal(pid1, pid2)
  end

  def make_tempfile
    t = Tempfile.new("test_io")
    t.binmode
    t.puts "foo"
    t.puts "bar"
    t.puts "baz"
    t.close
    if block_given?
      begin
        yield t
      ensure
        t.close(true)
      end
    else
      t
    end
  end

  def test_set_lineno
    make_tempfile {|t|
      assert_separately(["-", t.path], <<-SRC)
        open(ARGV[0]) do |f|
          assert_equal(0, $.)
          f.gets; assert_equal(1, $.)
          f.gets; assert_equal(2, $.)
          f.lineno = 1000; assert_equal(2, $.)
          f.gets; assert_equal(1001, $.)
          f.gets; assert_equal(1001, $.)
          f.rewind; assert_equal(1001, $.)
          f.gets; assert_equal(1, $.)
          f.gets; assert_equal(2, $.)
          f.gets; assert_equal(3, $.)
          f.gets; assert_equal(3, $.)
        end
      SRC
    }
  end

  def test_set_lineno_gets
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

  def test_set_lineno_readline
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
    verbose, $VERBOSE = $VERBOSE, nil
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      e = nil
      assert_warn(/deprecated/) {
        e = r.lines
      }
      assert_equal("foo\n", e.next)
      assert_equal("bar\n", e.next)
      assert_equal("baz\n", e.next)
      assert_raise(StopIteration) { e.next }
    end)
  ensure
    $VERBOSE = verbose
  end

  def test_bytes
    verbose, $VERBOSE = $VERBOSE, nil
    pipe(proc do |w|
      w.binmode
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      e = nil
      assert_warn(/deprecated/) {
        e = r.bytes
      }
      (%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"]).each do |c|
        assert_equal(c.ord, e.next)
      end
      assert_raise(StopIteration) { e.next }
    end)
  ensure
    $VERBOSE = verbose
  end

  def test_chars
    verbose, $VERBOSE = $VERBOSE, nil
    pipe(proc do |w|
      w.puts "foo"
      w.puts "bar"
      w.puts "baz"
      w.close
    end, proc do |r|
      e = nil
      assert_warn(/deprecated/) {
        e = r.chars
      }
      (%w(f o o) + ["\n"] + %w(b a r) + ["\n"] + %w(b a z) + ["\n"]).each do |c|
        assert_equal(c, e.next)
      end
      assert_raise(StopIteration) { e.next }
    end)
  ensure
    $VERBOSE = verbose
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
    ruby do |f|
      assert_equal(true, f.close_on_exec?)
      f.close_on_exec = false
      assert_equal(false, f.close_on_exec?)
      f.close_on_exec = true
      assert_equal(true, f.close_on_exec?)
      f.close_on_exec = false
      assert_equal(false, f.close_on_exec?)
    end

    with_pipe do |r, w|
      assert_equal(true, r.close_on_exec?)
      r.close_on_exec = false
      assert_equal(false, r.close_on_exec?)
      r.close_on_exec = true
      assert_equal(true, r.close_on_exec?)
      r.close_on_exec = false
      assert_equal(false, r.close_on_exec?)

      assert_equal(true, w.close_on_exec?)
      w.close_on_exec = false
      assert_equal(false, w.close_on_exec?)
      w.close_on_exec = true
      assert_equal(true, w.close_on_exec?)
      w.close_on_exec = false
      assert_equal(false, w.close_on_exec?)
    end
  end if have_close_on_exec?

  def test_pos
    make_tempfile {|t|
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
    }
  end

  def test_pos_with_getc
    _bug6179 = '[ruby-core:43497]'
    make_tempfile {|t|
      ["", "t", "b"].each do |mode|
        open(t.path, "w#{mode}") do |f|
          f.write "0123456789\n"
        end

        open(t.path, "r#{mode}") do |f|
          assert_equal 0, f.pos, "mode=r#{mode}"
          assert_equal '0', f.getc, "mode=r#{mode}"
          assert_equal 1, f.pos, "mode=r#{mode}"
          assert_equal '1', f.getc, "mode=r#{mode}"
          assert_equal 2, f.pos, "mode=r#{mode}"
          assert_equal '2', f.getc, "mode=r#{mode}"
          assert_equal 3, f.pos, "mode=r#{mode}"
          assert_equal '3', f.getc, "mode=r#{mode}"
          assert_equal 4, f.pos, "mode=r#{mode}"
          assert_equal '4', f.getc, "mode=r#{mode}"
        end
      end
    }
  end

  def can_seek_data(f)
    if /linux/ =~ RUBY_PLATFORM
      require "-test-/file"
      # lseek(2)
      case Bug::File::Fs.fsname(f.path)
      when "btrfs"
        return true if (Etc.uname[:release].split('.').map(&:to_i) <=> [3,1]) >= 0
      when "ocfs"
        return true if (Etc.uname[:release].split('.').map(&:to_i) <=> [3,2]) >= 0
      when "xfs"
        return true if (Etc.uname[:release].split('.').map(&:to_i) <=> [3,5]) >= 0
      when "ext4"
        return true if (Etc.uname[:release].split('.').map(&:to_i) <=> [3,8]) >= 0
      when "tmpfs"
        return true if (Etc.uname[:release].split('.').map(&:to_i) <=> [3,8]) >= 0
      end
    end
    false
  end

  def test_seek
    make_tempfile {|t|
      open(t.path) { |f|
        f.seek(9)
        assert_equal("az\n", f.read)
      }

      open(t.path) { |f|
        f.seek(9, IO::SEEK_SET)
        assert_equal("az\n", f.read)
      }

      open(t.path) { |f|
        f.seek(-4, IO::SEEK_END)
        assert_equal("baz\n", f.read)
      }

      open(t.path) { |f|
        assert_equal("foo\n", f.gets)
        f.seek(2, IO::SEEK_CUR)
        assert_equal("r\nbaz\n", f.read)
      }

      if defined?(IO::SEEK_DATA)
        open(t.path) { |f|
          break unless can_seek_data(f)
          assert_equal("foo\n", f.gets)
          f.seek(0, IO::SEEK_DATA)
          assert_equal("foo\nbar\nbaz\n", f.read)
        }
        open(t.path, 'r+') { |f|
          break unless can_seek_data(f)
          f.seek(100*1024, IO::SEEK_SET)
          f.print("zot\n")
          f.seek(50*1024, IO::SEEK_DATA)
          assert_operator(f.pos, :>=, 50*1024)
          assert_match(/\A\0*zot\n\z/, f.read)
        }
      end

      if defined?(IO::SEEK_HOLE)
        open(t.path) { |f|
          break unless can_seek_data(f)
          assert_equal("foo\n", f.gets)
          f.seek(0, IO::SEEK_HOLE)
          assert_operator(f.pos, :>, 20)
          f.seek(100*1024, IO::SEEK_HOLE)
          assert_equal("", f.read)
        }
      end
    }
  end

  def test_seek_symwhence
    make_tempfile {|t|
      open(t.path) { |f|
        f.seek(9, :SET)
        assert_equal("az\n", f.read)
      }

      open(t.path) { |f|
        f.seek(-4, :END)
        assert_equal("baz\n", f.read)
      }

      open(t.path) { |f|
        assert_equal("foo\n", f.gets)
        f.seek(2, :CUR)
        assert_equal("r\nbaz\n", f.read)
      }

      if defined?(IO::SEEK_DATA)
        open(t.path) { |f|
          break unless can_seek_data(f)
          assert_equal("foo\n", f.gets)
          f.seek(0, :DATA)
          assert_equal("foo\nbar\nbaz\n", f.read)
        }
        open(t.path, 'r+') { |f|
          break unless can_seek_data(f)
          f.seek(100*1024, :SET)
          f.print("zot\n")
          f.seek(50*1024, :DATA)
          assert_operator(f.pos, :>=, 50*1024)
          assert_match(/\A\0*zot\n\z/, f.read)
        }
      end

      if defined?(IO::SEEK_HOLE)
        open(t.path) { |f|
          break unless can_seek_data(f)
          assert_equal("foo\n", f.gets)
          f.seek(0, :HOLE)
          assert_operator(f.pos, :>, 20)
          f.seek(100*1024, :HOLE)
          assert_equal("", f.read)
        }
      end
    }
  end

  def test_sysseek
    make_tempfile {|t|
      open(t.path) do |f|
        f.sysseek(-4, IO::SEEK_END)
        assert_equal("baz\n", f.read)
      end

      open(t.path) do |f|
        a = [f.getc, f.getc, f.getc]
        a.reverse_each {|c| f.ungetc c }
        assert_raise(IOError) { f.sysseek(1) }
      end
    }
  end

  def test_syswrite
    make_tempfile {|t|
      open(t.path, "w") do |f|
        o = Object.new
        def o.to_s; "FOO\n"; end
        f.syswrite(o)
      end
      assert_equal("FOO\n", File.read(t.path))
    }
  end

  def test_sysread
    make_tempfile {|t|
      open(t.path) do |f|
        a = [f.getc, f.getc, f.getc]
        a.reverse_each {|c| f.ungetc c }
        assert_raise(IOError) { f.sysread(1) }
      end
    }
  end

  def test_sysread_with_not_empty_buffer
    pipe(proc do |w|
      w.write "foob"
      w.close
    end, proc do |r|
      r.sysread( 5, s = "01234567" )
      assert_equal( "foob", s )
    end)
  end

  def test_flag
    make_tempfile {|t|
      assert_raise(ArgumentError) do
        open(t.path, "z") { }
      end

      assert_raise(ArgumentError) do
        open(t.path, "rr") { }
      end

      assert_raise(ArgumentError) do
        open(t.path, "rbt") { }
      end
    }
  end

  def test_sysopen
    make_tempfile {|t|
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
    }
  end

  def try_fdopen(fd, autoclose = true, level = 50)
    if level > 0
      begin
        1.times {return try_fdopen(fd, autoclose, level - 1)}
      ensure
        GC.start
      end
    else
      WeakRef.new(IO.for_fd(fd, autoclose: autoclose))
    end
  end

  def test_autoclose
    feature2250 = '[ruby-core:26222]'
    pre = 'ft2250'

    Dir.mktmpdir {|d|
      t = open("#{d}/#{pre}", "w")
      f = IO.for_fd(t.fileno)
      assert_equal(true, f.autoclose?)
      f.autoclose = false
      assert_equal(false, f.autoclose?)
      f.close
      assert_nothing_raised(Errno::EBADF, feature2250) {t.close}

      t = open("#{d}/#{pre}", "w")
      f = IO.for_fd(t.fileno, autoclose: false)
      assert_equal(false, f.autoclose?)
      f.autoclose = true
      assert_equal(true, f.autoclose?)
      f.close
      assert_raise(Errno::EBADF, feature2250) {t.close}
    }
  end

  def test_autoclose_true_closed_by_finalizer
    # http://ci.rvm.jp/results/trunk-mjit@silicon-docker/1465760
    # http://ci.rvm.jp/results/trunk-mjit@silicon-docker/1469765
    skip 'this randomly fails with MJIT' if RubyVM::MJIT.enabled?

    feature2250 = '[ruby-core:26222]'
    pre = 'ft2250'
    t = Tempfile.new(pre)
    w = try_fdopen(t.fileno)
    begin
      w.close
      begin
        t.close
      rescue Errno::EBADF
      end
      skip "expect IO object was GC'ed but not recycled yet"
    rescue WeakRef::RefError
      assert_raise(Errno::EBADF, feature2250) {t.close}
    end
  ensure
    t&.close!
  end

  def test_autoclose_false_closed_by_finalizer
    feature2250 = '[ruby-core:26222]'
    pre = 'ft2250'
    t = Tempfile.new(pre)
    w = try_fdopen(t.fileno, false)
    begin
      w.close
      t.close
      skip "expect IO object was GC'ed but not recycled yet"
    rescue WeakRef::RefError
      assert_nothing_raised(Errno::EBADF, feature2250) {t.close}
    end
  ensure
    t.close!
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

  def test_read_command
    assert_equal("foo\n", IO.read("|echo foo"))
    assert_raise(Errno::ENOENT, Errno::EINVAL) do
      File.read("|#{EnvUtil.rubybin} -e puts")
    end
    assert_raise(Errno::ENOENT, Errno::EINVAL) do
      File.binread("|#{EnvUtil.rubybin} -e puts")
    end
    assert_raise(Errno::ENOENT, Errno::EINVAL) do
      Class.new(IO).read("|#{EnvUtil.rubybin} -e puts")
    end
    assert_raise(Errno::ENOENT, Errno::EINVAL) do
      Class.new(IO).binread("|#{EnvUtil.rubybin} -e puts")
    end
    assert_raise(Errno::ESPIPE) do
      IO.read("|echo foo", 1, 1)
    end
  end

  def test_reopen
    make_tempfile {|t|
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
        begin
          f2.gets
          assert_nothing_raised {
            f.reopen(f2)
            assert_equal("bar\n", f.gets, '[ruby-core:24240]')
          }
        ensure
          f2.close
        end
      end

      open(__FILE__) do |f|
        f2 = open(t.path)
        begin
          f.reopen(f2)
          assert_equal("foo\n", f.gets)
          assert_equal("bar\n", f.gets)
          f.reopen(f2)
          assert_equal("baz\n", f.gets, '[ruby-dev:39479]')
        ensure
          f2.close
        end
      end
    }
  end

  def test_reopen_inherit
    mkcdtmpdir {
      system(EnvUtil.rubybin, '-e', <<-"End")
        f = open("out", "w")
        STDOUT.reopen(f)
        STDERR.reopen(f)
        system(#{EnvUtil.rubybin.dump}, '-e', 'STDOUT.print "out"')
        system(#{EnvUtil.rubybin.dump}, '-e', 'STDERR.print "err"')
      End
      assert_equal("outerr", File.read("out"))
    }
  end

  def test_reopen_stdio
    mkcdtmpdir {
      fname = 'bug11319'
      File.write(fname, 'hello')
      system(EnvUtil.rubybin, '-e', "STDOUT.reopen('#{fname}', 'w+')")
      assert_equal('', File.read(fname))
    }
  end

  def test_reopen_mode
    feature7067 = '[ruby-core:47694]'
    make_tempfile {|t|
      open(__FILE__) do |f|
        assert_nothing_raised {
          f.reopen(t.path, "r")
          assert_equal("foo\n", f.gets)
        }
      end

      open(__FILE__) do |f|
        assert_nothing_raised(feature7067) {
          f.reopen(t.path, File::RDONLY)
          assert_equal("foo\n", f.gets)
        }
      end
    }
  end

  def test_reopen_opt
    feature7103 = '[ruby-core:47806]'
    make_tempfile {|t|
      open(__FILE__) do |f|
        assert_nothing_raised(feature7103) {
          f.reopen(t.path, "r", binmode: true)
        }
        assert_equal("foo\n", f.gets)
      end

      open(__FILE__) do |f|
        assert_nothing_raised(feature7103) {
          f.reopen(t.path, autoclose: false)
        }
        assert_equal("foo\n", f.gets)
      end
    }
  end

  def make_tempfile_for_encoding
    t = make_tempfile
    open(t.path, "rb+:utf-8") {|f| f.puts "\u7d05\u7389bar\n"}
    if block_given?
      yield t
    else
      t
    end
  ensure
    t&.close(true) if block_given?
  end

  def test_reopen_encoding
    make_tempfile_for_encoding {|t|
      open(__FILE__) {|f|
        f.reopen(t.path, "r:utf-8")
        s = f.gets
        assert_equal(Encoding::UTF_8, s.encoding)
        assert_equal("\u7d05\u7389bar\n", s)
      }

      open(__FILE__) {|f|
        f.reopen(t.path, "r:UTF-8:EUC-JP")
        s = f.gets
        assert_equal(Encoding::EUC_JP, s.encoding)
        assert_equal("\xB9\xC8\xB6\xCCbar\n".force_encoding(Encoding::EUC_JP), s)
      }
    }
  end

  def test_reopen_opt_encoding
    feature7103 = '[ruby-core:47806]'
    make_tempfile_for_encoding {|t|
      open(__FILE__) {|f|
        assert_nothing_raised(feature7103) {f.reopen(t.path, encoding: "ASCII-8BIT")}
        s = f.gets
        assert_equal(Encoding::ASCII_8BIT, s.encoding)
        assert_equal("\xe7\xb4\x85\xe7\x8e\x89bar\n", s)
      }

      open(__FILE__) {|f|
        assert_nothing_raised(feature7103) {f.reopen(t.path, encoding: "UTF-8:EUC-JP")}
        s = f.gets
        assert_equal(Encoding::EUC_JP, s.encoding)
        assert_equal("\xB9\xC8\xB6\xCCbar\n".force_encoding(Encoding::EUC_JP), s)
      }
    }
  end

  bug11320 = '[ruby-core:69780] [Bug #11320]'
  ["UTF-8", "EUC-JP", "Shift_JIS"].each do |enc|
    define_method("test_reopen_nonascii(#{enc})") do
      mkcdtmpdir do
        fname = "\u{30eb 30d3 30fc}".encode(enc)
        File.write(fname, '')
        assert_file.exist?(fname)
        stdin = $stdin.dup
        begin
          assert_nothing_raised(Errno::ENOENT, "#{bug11320}: #{enc}") {
            $stdin.reopen(fname, 'r')
          }
        ensure
          $stdin.reopen(stdin)
          stdin.close
        end
      end
    end
  end

  def test_foreach
    a = []
    IO.foreach("|" + EnvUtil.rubybin + " -e 'puts :foo; puts :bar; puts :baz'") {|x| a << x }
    assert_equal(["foo\n", "bar\n", "baz\n"], a)

    a = []
    IO.foreach("|" + EnvUtil.rubybin + " -e 'puts :zot'", :open_args => ["r"]) {|x| a << x }
    assert_equal(["zot\n"], a)

    make_tempfile {|t|
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

      bug = '[ruby-dev:31525]'
      assert_raise(ArgumentError, bug) {IO.foreach}

      a = nil
      assert_nothing_raised(ArgumentError, bug) {a = IO.foreach(t.path).to_a}
      assert_equal(["foo\n", "bar\n", "baz\n"], a, bug)

      bug6054 = '[ruby-dev:45267]'
      assert_raise_with_message(IOError, /not opened for reading/, bug6054) do
        IO.foreach(t.path, mode:"w").next
      end
    }
  end

  def test_s_readlines
    make_tempfile {|t|
      assert_equal(["foo\n", "bar\n", "baz\n"], IO.readlines(t.path))
      assert_equal(["foo\nb", "ar\nb", "az\n"], IO.readlines(t.path, "b"))
      assert_equal(["fo", "o\n", "ba", "r\n", "ba", "z\n"], IO.readlines(t.path, 2))
      assert_equal(["fo", "o\n", "b", "ar", "\nb", "az", "\n"], IO.readlines(t.path, "b", 2))
    }
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
    make_tempfile {|t|
      assert_in_out_err(["-", t.path],
                        "print while $<.gets",
                        %w(foo bar baz), [])
    }
  end

  def test_print_separators
    EnvUtil.suppress_warning {$, = ':'}
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

  def test_puts_parallel
    skip "not portable"
    pipe(proc do |w|
      threads = []
      100.times do
        threads << Thread.new { w.puts "hey" }
      end
      threads.each(&:join)
      w.close
    end, proc do |r|
      assert_equal("hey\n" * 100, r.read)
    end)
  end

  def test_puts_old_write
    capture = String.new
    def capture.write(str)
      self << str
    end

    capture.clear
    assert_warning(/[.#]write is outdated/) do
      stdout, $stdout = $stdout, capture
      puts "hey"
    ensure
      $stdout = stdout
    end
    assert_equal("hey\n", capture)
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

    assert_separately(%w[-Eutf-8], "#{<<~"begin;"}\n#{<<~"end;"}")
    begin;
      alias $\u{6a19 6e96 51fa 529b} $stdout
      x = eval("class X\u{307b 3052}; self; end".encode("euc-jp"))
      assert_raise_with_message(TypeError, /\\$\u{6a19 6e96 51fa 529b} must.*, X\u{307b 3052} given/) do
        $\u{6a19 6e96 51fa 529b} = x.new
      end
    end;
  end

  def test_initialize
    return unless defined?(Fcntl::F_GETFL)

    make_tempfile {|t|
      fd = IO.sysopen(t.path, "w")
      assert_kind_of(Integer, fd)
      %w[r r+ w+ a+].each do |mode|
        assert_raise(Errno::EINVAL, "#{mode} [ruby-dev:38571]") {IO.new(fd, mode)}
      end
      f = IO.new(fd, "w")
      f.write("FOO\n")
      f.close

      assert_equal("FOO\n", File.read(t.path))
    }
  end

  def test_reinitialize
    make_tempfile {|t|
      f = open(t.path)
      begin
        assert_raise(RuntimeError) do
          f.instance_eval { initialize }
        end
      ensure
        f.close
      end
    }
  end

  def test_new_with_block
    assert_in_out_err([], "r, w = IO.pipe; r.autoclose=false; IO.new(r.fileno) {}.close", [], /^.+$/)
    n = "IO\u{5165 51fa 529b}"
    c = eval("class #{n} < IO; self; end")
    IO.pipe do |r, w|
      assert_warning(/#{n}/) {
        r.autoclose=false
        io = c.new(r.fileno) {}
        io.close
      }
    end
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
    make_tempfile {|t|
      assert_equal("foo\nbar\nbaz\n", File.read(t.path))
      assert_equal("foo\nba", File.read(t.path, 6))
      assert_equal("bar\n", File.read(t.path, 4, 4))
    }
  end

  def test_uninitialized
    assert_raise(IOError) { IO.allocate.print "" }
  end

  def test_nofollow
    # O_NOFOLLOW is not standard.
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
  end if /freebsd|linux/ =~ RUBY_PLATFORM and defined? File::NOFOLLOW

  def test_tainted
    make_tempfile {|t|
      assert_predicate(File.read(t.path, 4), :tainted?, '[ruby-dev:38826]')
      assert_predicate(File.open(t.path) {|f| f.read(4)}, :tainted?, '[ruby-dev:38826]')
    }
  end

  def test_binmode_after_closed
    make_tempfile {|t|
      assert_raise(IOError) {t.binmode}
    }
  end

  def test_DATA_binmode
    assert_separately([], <<-SRC)
assert_not_predicate(DATA, :binmode?)
__END__
    SRC
  end

  def test_threaded_flush
    bug3585 = '[ruby-core:31348]'
    src = "#{<<~"begin;"}\n#{<<~'end;'}"
    begin;
      t = Thread.new { sleep 3 }
      Thread.new {sleep 1; t.kill; p 'hi!'}
      t.join
    end;
    10.times.map do
      Thread.start do
        assert_in_out_err([], src, timeout: 20) {|stdout, stderr|
          assert_no_match(/hi.*hi/, stderr.join, bug3585)
        }
      end
    end.each {|th| th.join}
  end

  def test_flush_in_finalizer1
    bug3910 = '[ruby-dev:42341]'
    tmp = Tempfile.open("bug3910") {|t|
      path = t.path
      t.close
      fds = []
      assert_nothing_raised(TypeError, bug3910) do
        500.times {
          f = File.open(path, "w")
          f.instance_variable_set(:@test_flush_in_finalizer1, true)
          fds << f.fileno
          f.print "hoge"
        }
      end
      t
    }
  ensure
    ObjectSpace.each_object(File) {|f|
      if f.instance_variables.include?(:@test_flush_in_finalizer1)
        f.close
      end
    }
    tmp.close!
  end

  def test_flush_in_finalizer2
    bug3910 = '[ruby-dev:42341]'
    Tempfile.open("bug3910") {|t|
      path = t.path
      t.close
      begin
        1.times do
          io = open(path,"w")
          io.instance_variable_set(:@test_flush_in_finalizer2, true)
          io.print "hoge"
        end
        assert_nothing_raised(TypeError, bug3910) do
          GC.start
        end
      ensure
        ObjectSpace.each_object(File) {|f|
          if f.instance_variables.include?(:@test_flush_in_finalizer2)
            f.close
          end
        }
      end
      t.close!
    }
  end

  def test_readlines_limit_0
    bug4024 = '[ruby-dev:42538]'
    make_tempfile {|t|
      open(t.path, "r") do |io|
        assert_raise(ArgumentError, bug4024) do
          io.readlines(0)
        end
      end
    }
  end

  def test_each_line_limit_0
    bug4024 = '[ruby-dev:42538]'
    make_tempfile {|t|
      open(t.path, "r") do |io|
        assert_raise(ArgumentError, bug4024) do
          io.each_line(0).next
        end
      end
    }
  end

  def os_and_fs(path)
    uname = Etc.uname
    os = "#{uname[:sysname]} #{uname[:release]}"

    fs = nil
    if uname[:sysname] == 'Linux'
      # [ruby-dev:45703] Old Linux's fadvise() doesn't work on tmpfs.
      mount = `mount`
      mountpoints = []
      mount.scan(/ on (\S+) type (\S+) /) {
        mountpoints << [$1, $2]
      }
      mountpoints.sort_by {|mountpoint, fstype| mountpoint.length }.reverse_each {|mountpoint, fstype|
        if path == mountpoint
          fs = fstype
          break
        end
        mountpoint += "/" if %r{/\z} !~ mountpoint
        if path.start_with?(mountpoint)
          fs = fstype
          break
        end
      }
    end

    if fs
      "#{fs} on #{os}"
    else
      os
    end
  end

  def test_advise
    make_tempfile {|tf|
      assert_raise(ArgumentError, "no arguments") { tf.advise }
      %w{normal random sequential willneed dontneed noreuse}.map(&:to_sym).each do |adv|
        [[0,0], [0, 20], [400, 2]].each do |offset, len|
          open(tf.path) do |t|
            ret = assert_nothing_raised(lambda { os_and_fs(tf.path) }) {
              begin
                t.advise(adv, offset, len)
              rescue Errno::EINVAL => e
                if /linux/ =~ RUBY_PLATFORM && (Etc.uname[:release].split('.').map(&:to_i) <=> [3,6]) < 0
                  next # [ruby-core:65355] tmpfs is not supported
                else
                  raise e
                end
              end
            }
            assert_nil(ret)
            assert_raise(ArgumentError, "superfluous arguments") do
              t.advise(adv, offset, len, offset)
            end
            assert_raise(TypeError, "wrong type for first argument") do
              t.advise(adv.to_s, offset, len)
            end
            assert_raise(TypeError, "wrong type for last argument") do
              t.advise(adv, offset, Array(len))
            end
            assert_raise(RangeError, "last argument too big") do
              t.advise(adv, offset, 9999e99)
            end
          end
          assert_raise(IOError, "closed file") do
            make_tempfile {|tf2|
              tf2.advise(adv.to_sym, offset, len)
            }
          end
        end
      end
    }
  end

  def test_invalid_advise
    feature4204 = '[ruby-dev:42887]'
    make_tempfile {|tf|
      %W{Normal rand glark will_need zzzzzzzzzzzz \u2609}.map(&:to_sym).each do |adv|
        [[0,0], [0, 20], [400, 2]].each do |offset, len|
          open(tf.path) do |t|
            assert_raise_with_message(NotImplementedError, /#{Regexp.quote(adv.inspect)}/, feature4204) { t.advise(adv, offset, len) }
          end
        end
      end
    }
  end

  def test_fcntl_lock_linux
    pad = 0
    Tempfile.create(self.class.name) do |f|
      r, w = IO.pipe
      pid = fork do
        r.close
        lock = [Fcntl::F_WRLCK, IO::SEEK_SET, pad, 12, 34, 0].pack("s!s!i!L!L!i!")
        f.fcntl Fcntl::F_SETLKW, lock
        w.syswrite "."
        sleep
      end
      w.close
      assert_equal ".", r.read(1)
      r.close
      pad = 0
      getlock = [Fcntl::F_WRLCK, 0, pad, 0, 0, 0].pack("s!s!i!L!L!i!")
      f.fcntl Fcntl::F_GETLK, getlock

      ptype, whence, pad, start, len, lockpid = getlock.unpack("s!s!i!L!L!i!")

      assert_equal(ptype, Fcntl::F_WRLCK)
      assert_equal(whence, IO::SEEK_SET)
      assert_equal(start, 12)
      assert_equal(len, 34)
      assert_equal(pid, lockpid)

      Process.kill :TERM, pid
      Process.waitpid2(pid)
    end
  end if /x86_64-linux/ =~ RUBY_PLATFORM and # A binary form of struct flock depend on platform
    [nil].pack("p").bytesize == 8 # unless x32 platform.

  def test_fcntl_lock_freebsd
    start = 12
    len = 34
    sysid = 0
    Tempfile.create(self.class.name) do |f|
      r, w = IO.pipe
      pid = fork do
        r.close
        lock = [start, len, 0, Fcntl::F_WRLCK, IO::SEEK_SET, sysid].pack("qqis!s!i!")
        f.fcntl Fcntl::F_SETLKW, lock
        w.syswrite "."
        sleep
      end
      w.close
      assert_equal ".", r.read(1)
      r.close

      getlock = [0, 0, 0, Fcntl::F_WRLCK, 0, 0].pack("qqis!s!i!")
      f.fcntl Fcntl::F_GETLK, getlock

      start, len, lockpid, ptype, whence, sysid = getlock.unpack("qqis!s!i!")

      assert_equal(ptype, Fcntl::F_WRLCK)
      assert_equal(whence, IO::SEEK_SET)
      assert_equal(start, 12)
      assert_equal(len, 34)
      assert_equal(pid, lockpid)

      Process.kill :TERM, pid
      Process.waitpid2(pid)
    end
  end if /freebsd/ =~ RUBY_PLATFORM # A binary form of struct flock depend on platform

  def test_fcntl_dupfd
    Tempfile.create(self.class.name) do |f|
      fd = f.fcntl(Fcntl::F_DUPFD, 63)
      begin
        assert_operator(fd, :>=, 63)
      ensure
        IO.for_fd(fd).close
      end
    end
  end

  def test_cross_thread_close_fd
    with_pipe do |r,w|
      read_thread = Thread.new do
        begin
          r.read(1)
        rescue => e
          e
        end
      end

      sleep(0.1) until read_thread.stop?
      r.close
      read_thread.join
      assert_kind_of(IOError, read_thread.value)
    end
  end

  def test_cross_thread_close_stdio
    assert_separately([], <<-'end;')
      IO.pipe do |r,w|
        $stdin.reopen(r)
        r.close
        read_thread = Thread.new do
          begin
            $stdin.read(1)
          rescue IOError => e
            e
          end
        end
        sleep(0.1) until read_thread.stop?
        $stdin.close
        assert_kind_of(IOError, read_thread.value)
      end
    end;
  end

  def test_single_exception_on_close
    a = []
    t = []
    10.times do
      r, w = IO.pipe
      a << [r, w]
      t << Thread.new do
        while r.gets
        end rescue IOError
        Thread.current.pending_interrupt?
      end
    end
    a.each do |r, w|
      w.write(-"\n")
      w.close
      r.close
    end
    t.each do |th|
      assert_equal false, th.value, '[ruby-core:81581] [Bug #13632]'
    end
  end

  def test_open_mode
    feature4742 = "[ruby-core:36338]"
    bug6055 = '[ruby-dev:45268]'

    mkcdtmpdir do
      assert_not_nil(f = File.open('symbolic', 'w'))
      f.close
      assert_not_nil(f = File.open('numeric',  File::WRONLY|File::TRUNC|File::CREAT))
      f.close
      assert_not_nil(f = File.open('hash-symbolic', :mode => 'w'))
      f.close
      assert_not_nil(f = File.open('hash-numeric', :mode => File::WRONLY|File::TRUNC|File::CREAT), feature4742)
      f.close
      assert_nothing_raised(bug6055) {f = File.open('hash-symbolic', binmode: true)}
      f.close
    end
  end

  def test_s_write
    mkcdtmpdir do
      path = "test_s_write"
      File.write(path, "foo\nbar\nbaz")
      assert_equal("foo\nbar\nbaz", File.read(path))
      File.write(path, "FOO", 0)
      assert_equal("FOO\nbar\nbaz", File.read(path))
      File.write(path, "BAR")
      assert_equal("BAR", File.read(path))
      File.write(path, "\u{3042}", mode: "w", encoding: "EUC-JP")
      assert_equal("\u{3042}".encode("EUC-JP"), File.read(path, encoding: "EUC-JP"))
      File.delete path
      assert_equal(6, File.write(path, 'string', 2))
      File.delete path
      assert_raise(Errno::EINVAL) { File.write('nonexisting','string', -2) }
      assert_equal(6, File.write(path, 'string'))
      assert_equal(3, File.write(path, 'sub', 1))
      assert_equal("ssubng", File.read(path))
      File.delete path
      assert_equal(3, File.write(path, "foo", encoding: "UTF-8"))
      File.delete path
      assert_equal(3, File.write(path, "foo", 0, encoding: "UTF-8"))
      assert_equal("foo", File.read(path))
      assert_equal(1, File.write(path, "f", 1, encoding: "UTF-8"))
      assert_equal("ffo", File.read(path))
      File.delete path
      assert_equal(1, File.write(path, "f", 1, encoding: "UTF-8"))
      assert_equal("\00f", File.read(path))
      assert_equal(1, File.write(path, "f", 0, encoding: "UTF-8"))
      assert_equal("ff", File.read(path))
      assert_raise(TypeError) {
        File.write(path, "foo", Object.new => Object.new)
      }
    end
  end

  def test_s_binread_does_not_leak_with_invalid_offset
    assert_raise(Errno::EINVAL) { IO.binread(__FILE__, 0, -1) }
  end

  def test_s_binwrite
    mkcdtmpdir do
      path = "test_s_binwrite"
      File.binwrite(path, "foo\nbar\nbaz")
      assert_equal("foo\nbar\nbaz", File.read(path))
      File.binwrite(path, "FOO", 0)
      assert_equal("FOO\nbar\nbaz", File.read(path))
      File.binwrite(path, "BAR")
      assert_equal("BAR", File.read(path))
      File.binwrite(path, "\u{3042}")
      assert_equal("\u{3042}".force_encoding("ASCII-8BIT"), File.binread(path))
      File.delete path
      assert_equal(6, File.binwrite(path, 'string', 2))
      File.delete path
      assert_equal(6, File.binwrite(path, 'string'))
      assert_equal(3, File.binwrite(path, 'sub', 1))
      assert_equal("ssubng", File.binread(path))
      assert_equal(6, File.size(path))
      assert_raise(Errno::EINVAL) { File.binwrite('nonexisting', 'string', -2) }
      assert_nothing_raised(TypeError) { File.binwrite(path, "string", mode: "w", encoding: "EUC-JP") }
    end
  end

  def test_race_between_read
    Tempfile.create("test") {|file|
      begin
        path = file.path
        file.close
        write_file = File.open(path, "wt")
        read_file = File.open(path, "rt")

        threads = []
        10.times do |i|
          threads << Thread.new {write_file.print(i)}
          threads << Thread.new {read_file.read}
        end
        assert_join_threads(threads)
        assert(true, "[ruby-core:37197]")
      ensure
        read_file.close
        write_file.close
      end
    }
  end

  def test_warn
    assert_warning "warning\n" do
      warn "warning"
    end

    assert_warning '' do
      warn
    end

    assert_warning "[Feature #5029]\n[ruby-core:38070]\n" do
      warn "[Feature #5029]", "[ruby-core:38070]"
    end
  end

  def test_cloexec
    return unless defined? Fcntl::FD_CLOEXEC
    open(__FILE__) {|f|
      assert_predicate(f, :close_on_exec?)
      g = f.dup
      begin
        assert_predicate(g, :close_on_exec?)
        f.reopen(g)
        assert_predicate(f, :close_on_exec?)
      ensure
        g.close
      end
      g = IO.new(f.fcntl(Fcntl::F_DUPFD))
      begin
        assert_predicate(g, :close_on_exec?)
      ensure
        g.close
      end
    }
    IO.pipe {|r,w|
      assert_predicate(r, :close_on_exec?)
      assert_predicate(w, :close_on_exec?)
    }
  end

  def test_ioctl_linux
    # Alpha, mips, sparc and ppc have an another ioctl request number scheme.
    # So, hardcoded 0x80045200 may fail.
    assert_nothing_raised do
      File.open('/dev/urandom'){|f1|
        entropy_count = ""
        # RNDGETENTCNT(0x80045200) mean "get entropy count".
        f1.ioctl(0x80045200, entropy_count)
      }
    end

    buf = ''
    assert_nothing_raised do
      fionread = 0x541B
      File.open(__FILE__){|f1|
        f1.ioctl(fionread, buf)
      }
    end
    assert_equal(File.size(__FILE__), buf.unpack('i!')[0])
  end if /^(?:i.?86|x86_64)-linux/ =~ RUBY_PLATFORM

  def test_ioctl_linux2
    return unless STDIN.tty? # stdin is not a terminal
    begin
      f = File.open('/dev/tty')
    rescue Errno::ENOENT, Errno::ENXIO => e
      skip e.message
    else
      tiocgwinsz=0x5413
      winsize=""
      assert_nothing_raised {
        f.ioctl(tiocgwinsz, winsize)
      }
    ensure
      f&.close
    end
  end if /^(?:i.?86|x86_64)-linux/ =~ RUBY_PLATFORM

  def test_setpos
    mkcdtmpdir {
      File.open("tmp.txt", "wb") {|f|
        f.puts "a"
        f.puts "bc"
        f.puts "def"
      }
      pos1 = pos2 = pos3 = nil
      File.open("tmp.txt", "rb") {|f|
        assert_equal("a\n", f.gets)
        pos1 = f.pos
        assert_equal("bc\n", f.gets)
        pos2 = f.pos
        assert_equal("def\n", f.gets)
        pos3 = f.pos
        assert_equal(nil, f.gets)
      }
      File.open("tmp.txt", "rb") {|f|
        f.pos = pos1
        assert_equal("bc\n", f.gets)
        assert_equal("def\n", f.gets)
        assert_equal(nil, f.gets)
      }
      File.open("tmp.txt", "rb") {|f|
        f.pos = pos2
        assert_equal("def\n", f.gets)
        assert_equal(nil, f.gets)
      }
      File.open("tmp.txt", "rb") {|f|
        f.pos = pos3
        assert_equal(nil, f.gets)
      }
      File.open("tmp.txt", "rb") {|f|
        f.pos = File.size("tmp.txt")
        s = "not empty string        "
        assert_equal("", f.read(0,s))
      }
    }
  end

  def test_std_fileno
    assert_equal(0, STDIN.fileno)
    assert_equal(1, STDOUT.fileno)
    assert_equal(2, STDERR.fileno)
    assert_equal(0, $stdin.fileno)
    assert_equal(1, $stdout.fileno)
    assert_equal(2, $stderr.fileno)
  end

  def test_frozen_fileno
    bug9865 = '[ruby-dev:48241] [Bug #9865]'
    with_pipe do |r,w|
      fd = r.fileno
      assert_equal(fd, r.freeze.fileno, bug9865)
    end
  end

  def test_frozen_autoclose
    with_pipe do |r,w|
      assert_equal(true, r.freeze.autoclose?)
    end
  end

  def test_sysread_locktmp
    bug6099 = '[ruby-dev:45297]'
    buf = " " * 100
    data = "a" * 100
    with_pipe do |r,w|
      th = Thread.new {r.sysread(100, buf)}
      Thread.pass until th.stop?
      buf.replace("")
      assert_empty(buf, bug6099)
      w.write(data)
      Thread.pass while th.alive?
      th.join
    end
    assert_equal(data, buf, bug6099)
  end

  def test_readpartial_locktmp
    bug6099 = '[ruby-dev:45297]'
    buf = " " * 100
    data = "a" * 100
    th = nil
    with_pipe do |r,w|
      r.nonblock = true
      th = Thread.new {r.readpartial(100, buf)}

      Thread.pass until th.stop?

      assert_equal 100, buf.bytesize

      msg = /can't modify string; temporarily locked/
      assert_raise_with_message(RuntimeError, msg) do
        buf.replace("")
      end
      assert_predicate(th, :alive?)
      w.write(data)
      th.join
    end
    assert_equal(data, buf, bug6099)
  end

  def test_advise_pipe
    # we don't know if other platforms have a real posix_fadvise()
    with_pipe do |r,w|
      # Linux 2.6.15 and earlier returned EINVAL instead of ESPIPE
      assert_raise(Errno::ESPIPE, Errno::EINVAL) {
        r.advise(:willneed) or skip "fadvise(2) is not implemented"
      }
      assert_raise(Errno::ESPIPE, Errno::EINVAL) {
        w.advise(:willneed) or skip "fadvise(2) is not implemented"
      }
    end
  end if /linux/ =~ RUBY_PLATFORM

  def assert_buffer_not_raise_shared_string_error
    bug6764 = '[ruby-core:46586]'
    bug9847 = '[ruby-core:62643] [Bug #9847]'
    size = 28
    data = [*"a".."z", *"A".."Z"].shuffle.join("")
    t = Tempfile.new("test_io")
    t.write(data)
    t.close
    w = []
    assert_nothing_raised(RuntimeError, bug6764) do
      buf = ''
      File.open(t.path, "r") do |r|
        while yield(r, size, buf)
          w << buf.dup
        end
      end
    end
    assert_equal(data, w.join(""), bug9847)
  ensure
    t.close!
  end

  def test_read_buffer_not_raise_shared_string_error
    assert_buffer_not_raise_shared_string_error do |r, size, buf|
      r.read(size, buf)
    end
  end

  def test_sysread_buffer_not_raise_shared_string_error
    assert_buffer_not_raise_shared_string_error do |r, size, buf|
      begin
        r.sysread(size, buf)
      rescue EOFError
        nil
      end
    end
  end

  def test_readpartial_buffer_not_raise_shared_string_error
    assert_buffer_not_raise_shared_string_error do |r, size, buf|
      begin
        r.readpartial(size, buf)
      rescue EOFError
        nil
      end
    end
  end

  def test_puts_recursive_ary
    bug5986 = '[ruby-core:42444]'
    c = Class.new {
      def to_ary
        [self]
      end
    }
    s = StringIO.new
    s.puts(c.new)
    assert_equal("[...]\n", s.string, bug5986)
  end

  def test_io_select_with_many_files
    bug8080 = '[ruby-core:53349]'

    assert_normal_exit %q{
      require "tempfile"

      # Unfortunately, ruby doesn't export FD_SETSIZE. then we assume it's 1024.
      fd_setsize = 1024

      # try to raise RLIM_NOFILE to >FD_SETSIZE
      begin
        Process.setrlimit(Process::RLIMIT_NOFILE, fd_setsize+20)
      rescue Errno::EPERM
        exit 0
      end

      tempfiles = []
      (0..fd_setsize+1).map {|i|
        tempfiles << Tempfile.open("test_io_select_with_many_files")
      }

      IO.select(tempfiles)
    }, bug8080, timeout: 100
  end if defined?(Process::RLIMIT_NOFILE)

  def test_read_32bit_boundary
    bug8431 = '[ruby-core:55098] [Bug #8431]'
    make_tempfile {|t|
      assert_separately(["-", bug8431, t.path], <<-"end;")
        msg = ARGV.shift
        f = open(ARGV[0], "rb")
        f.seek(0xffff_ffff)
        assert_nil(f.read(1), msg)
      end;
    }
  end if /mswin|mingw/ =~ RUBY_PLATFORM

  def test_write_32bit_boundary
    bug8431 = '[ruby-core:55098] [Bug #8431]'
    make_tempfile {|t|
      def t.close(unlink_now = false)
        # TODO: Tempfile should deal with this delay on Windows?
        # NOTE: re-opening with O_TEMPORARY does not work.
        path = self.path
        ret = super
        if unlink_now
          begin
            File.unlink(path)
          rescue Errno::ENOENT
          rescue Errno::EACCES
            sleep(2)
            retry
          end
        end
        ret
      end

      begin
        assert_separately(["-", bug8431, t.path], <<-"end;", timeout: 30)
          msg = ARGV.shift
          f = open(ARGV[0], "wb")
          f.seek(0xffff_ffff)
          begin
            # this will consume very long time or fail by ENOSPC on a
            # filesystem which sparse file is not supported
            f.write('1')
            pos = f.tell
          rescue Errno::ENOSPC
            skip "non-sparse file system"
          rescue SystemCallError
          else
            assert_equal(0x1_0000_0000, pos, msg)
          end
        end;
      rescue Timeout::Error
        skip "Timeout because of slow file writing"
      end
    }
  end if /mswin|mingw/ =~ RUBY_PLATFORM

  def test_read_unlocktmp_ensure
    bug8669 = '[ruby-core:56121] [Bug #8669]'

    str = ""
    IO.pipe {|r,|
      t = Thread.new {
        assert_raise(RuntimeError) {
          r.read(nil, str)
        }
      }
      sleep 0.1 until t.stop?
      t.raise
      sleep 0.1 while t.alive?
      assert_nothing_raised(RuntimeError, bug8669) { str.clear }
      t.join
    }
  end if /cygwin/ !~ RUBY_PLATFORM

  def test_readpartial_unlocktmp_ensure
    bug8669 = '[ruby-core:56121] [Bug #8669]'

    str = ""
    IO.pipe {|r, w|
      t = Thread.new {
        assert_raise(RuntimeError) {
          r.readpartial(4096, str)
        }
      }
      sleep 0.1 until t.stop?
      t.raise
      sleep 0.1 while t.alive?
      assert_nothing_raised(RuntimeError, bug8669) { str.clear }
      t.join
    }
  end if /cygwin/ !~ RUBY_PLATFORM

  def test_readpartial_bad_args
    IO.pipe do |r, w|
      w.write '.'
      buf = String.new
      assert_raise(ArgumentError) { r.readpartial(1, buf, exception: false) }
      assert_raise(TypeError) { r.readpartial(1, exception: false) }
      assert_equal [[r],[],[]], IO.select([r], nil, nil, 1)
      assert_equal '.', r.readpartial(1)
    end
  end

  def test_sysread_unlocktmp_ensure
    bug8669 = '[ruby-core:56121] [Bug #8669]'

    str = ""
    IO.pipe {|r, w|
      t = Thread.new {
        assert_raise(RuntimeError) {
          r.sysread(4096, str)
        }
      }
      sleep 0.1 until t.stop?
      t.raise
      sleep 0.1 while t.alive?
      assert_nothing_raised(RuntimeError, bug8669) { str.clear }
      t.join
    }
  end if /cygwin/ !~ RUBY_PLATFORM

  def test_exception_at_close
    bug10153 = '[ruby-core:64463] [Bug #10153] exception in close at the end of block'
    assert_raise(Errno::EBADF, bug10153) do
      IO.pipe do |r, w|
        assert_nothing_raised {IO.open(w.fileno) {}}
      end
    end
  end

  def test_close_twice
    open(__FILE__) {|f|
      assert_equal(nil, f.close)
      assert_equal(nil, f.close)
    }
  end

  def test_close_uninitialized
    io = IO.allocate
    assert_raise(IOError) { io.close }
  end

  def test_open_fifo_does_not_block_other_threads
    mkcdtmpdir {
      File.mkfifo("fifo")
      assert_separately([], <<-'EOS')
        t1 = Thread.new {
          open("fifo", "r") {|r|
            r.read
          }
        }
        t2 = Thread.new {
          open("fifo", "w") {|w|
            w.write "foo"
          }
        }
        t1_value, _ = assert_join_threads([t1, t2])
        assert_equal("foo", t1_value)
      EOS
    }
  end if /mswin|mingw|bccwin|cygwin/ !~ RUBY_PLATFORM

  def test_open_flag
    make_tempfile do |t|
      assert_raise(Errno::EEXIST){ open(t.path, File::WRONLY|File::CREAT, flags: File::EXCL){} }
      assert_raise(Errno::EEXIST){ open(t.path, 'w', flags: File::EXCL){} }
      assert_raise(Errno::EEXIST){ open(t.path, mode: 'w', flags: File::EXCL){} }
    end
  end

  def test_open_flag_binary
    make_tempfile do |t|
      open(t.path, File::RDONLY, flags: File::BINARY) do |f|
        assert_equal true, f.binmode?
      end
      open(t.path, 'r', flags: File::BINARY) do |f|
        assert_equal true, f.binmode?
      end
      open(t.path, mode: 'r', flags: File::BINARY) do |f|
        assert_equal true, f.binmode?
      end
    end
  end if File::BINARY != 0

  def test_exclusive_mode
    make_tempfile do |t|
      assert_raise(Errno::EEXIST){ open(t.path, 'wx'){} }
      assert_raise(ArgumentError){ open(t.path, 'rx'){} }
      assert_raise(ArgumentError){ open(t.path, 'ax'){} }
    end
  end

  def test_race_gets_and_close
    opt = { signal: :ABRT, timeout: 200 }
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}", opt)
    bug13076 = '[ruby-core:78845] [Bug #13076]'
    begin;
      10.times do |i|
        a = []
        t = []
        10.times do
          r,w = IO.pipe
          a << [r,w]
          t << Thread.new do
            begin
              while r.gets
              end
            rescue IOError
            end
          end
        end
        a.each do |r,w|
          w.puts "hoge"
          w.close
          r.close
        end
        t.each do |th|
          assert_same(th, th.join(2), bug13076)
        end
      end
    end;
  end

  def test_race_closed_stream
    assert_separately([], "#{<<-"begin;"}\n#{<<-"end;"}")
    begin;
      bug13158 = '[ruby-core:79262] [Bug #13158]'
      closed = nil
      q = Queue.new
      IO.pipe do |r, w|
        thread = Thread.new do
          begin
            q << true
            assert_raise_with_message(IOError, /stream closed/) do
              while r.gets
              end
            end
          ensure
            closed = r.closed?
          end
        end
        q.pop
        sleep 0.01 until thread.stop?
        r.close
        thread.join
        assert_equal(true, closed, bug13158 + ': stream should be closed')
      end
    end;
  end

  if RUBY_ENGINE == "ruby" # implementation details
    def test_foreach_rs_conversion
      make_tempfile {|t|
        a = []
        rs = Struct.new(:count).new(0)
        def rs.to_str; self.count += 1; "\n"; end
        IO.foreach(t.path, rs) {|x| a << x }
        assert_equal(["foo\n", "bar\n", "baz\n"], a)
        assert_equal(1, rs.count)
      }
    end

    def test_foreach_rs_invalid
      make_tempfile {|t|
        rs = Object.new
        def rs.to_str; raise "invalid rs"; end
        assert_raise(RuntimeError) do
          IO.foreach(t.path, rs, mode:"w") {}
        end
        assert_equal(["foo\n", "bar\n", "baz\n"], IO.foreach(t.path).to_a)
      }
    end

    def test_foreach_limit_conversion
      make_tempfile {|t|
        a = []
        lim = Struct.new(:count).new(0)
        def lim.to_int; self.count += 1; -1; end
        IO.foreach(t.path, lim) {|x| a << x }
        assert_equal(["foo\n", "bar\n", "baz\n"], a)
        assert_equal(1, lim.count)
      }
    end

    def test_foreach_limit_invalid
      make_tempfile {|t|
        lim = Object.new
        def lim.to_int; raise "invalid limit"; end
        assert_raise(RuntimeError) do
          IO.foreach(t.path, lim, mode:"w") {}
        end
        assert_equal(["foo\n", "bar\n", "baz\n"], IO.foreach(t.path).to_a)
      }
    end

    def test_readlines_rs_invalid
      make_tempfile {|t|
        rs = Object.new
        def rs.to_str; raise "invalid rs"; end
        assert_raise(RuntimeError) do
          IO.readlines(t.path, rs, mode:"w")
        end
        assert_equal(["foo\n", "bar\n", "baz\n"], IO.readlines(t.path))
      }
    end

    def test_readlines_limit_invalid
      make_tempfile {|t|
        lim = Object.new
        def lim.to_int; raise "invalid limit"; end
        assert_raise(RuntimeError) do
          IO.readlines(t.path, lim, mode:"w")
        end
        assert_equal(["foo\n", "bar\n", "baz\n"], IO.readlines(t.path))
      }
    end

    def test_closed_stream_in_rescue
      assert_separately([], "#{<<-"begin;"}\n#{<<~"end;"}")
      begin;
      10.times do
        assert_nothing_raised(RuntimeError, /frozen IOError/) do
          IO.pipe do |r, w|
            th = Thread.start {r.close}
            r.gets
          rescue IOError
            # swallow pending exceptions
            begin
              sleep 0.001
            rescue IOError
              retry
            end
          ensure
            th.kill.join
          end
        end
      end
      end;
    end

    def test_write_no_garbage
      skip "multiple threads already active" if Thread.list.size > 1
      res = {}
      ObjectSpace.count_objects(res) # creates strings on first call
      [ 'foo'.b, '*' * 24 ].each do |buf|
        with_pipe do |r, w|
          GC.disable
          begin
            before = ObjectSpace.count_objects(res)[:T_STRING]
            n = w.write(buf)
            s = w.syswrite(buf)
            after = ObjectSpace.count_objects(res)[:T_STRING]
          ensure
            GC.enable
          end
          assert_equal before, after,
            "no strings left over after write [ruby-core:78898] [Bug #13085]: #{ before } strings before write -> #{ after } strings after write"
          assert_not_predicate buf, :frozen?, 'no inadvertent freeze'
          assert_equal buf.bytesize, n, 'IO#write wrote expected size'
          assert_equal s, n, 'IO#syswrite wrote expected size'
        end
      end
    end

    def test_pread
      make_tempfile { |t|
        open(t.path) do |f|
          assert_equal("bar", f.pread(3, 4))
          buf = "asdf"
          assert_equal("bar", f.pread(3, 4, buf))
          assert_equal("bar", buf)
          assert_raise(EOFError) { f.pread(1, f.size) }
        end
      }
    end if IO.method_defined?(:pread)

    def test_pwrite
      make_tempfile { |t|
        open(t.path, IO::RDWR) do |f|
          assert_equal(3, f.pwrite("ooo", 4))
          assert_equal("ooo", f.pread(3, 4))
        end
      }
    end if IO.method_defined?(:pread) and IO.method_defined?(:pwrite)
  end

  def test_select_exceptfds
    if Etc.uname[:sysname] == 'SunOS' && Etc.uname[:release] == '5.11'
      skip "Solaris 11 fails this"
    end

    TCPServer.open('localhost', 0) do |svr|
      con = TCPSocket.new('localhost', svr.addr[1])
      acc = svr.accept
      assert_equal 5, con.send('hello', Socket::MSG_OOB)
      set = IO.select(nil, nil, [acc], 30)
      assert_equal([[], [], [acc]], set, 'IO#select exceptions array OK')
      acc.close
      con.close
    end
  end if Socket.const_defined?(:MSG_OOB)

  def test_recycled_fd_close
    dot = -'.'
    IO.pipe do |sig_rd, sig_wr|
      noex = Thread.new do # everything right and never see exceptions :)
        until sig_rd.wait_readable(0)
          IO.pipe do |r, w|
            th = Thread.new { r.read(1) }
            w.write(dot)

            assert_same th, th.join(15), '"good" reader timeout'
            assert_equal(dot, th.value)
          end
        end
        sig_rd.read(4)
      end
      1000.times do |i| # stupid things and make exceptions:
        IO.pipe do |r,w|
          th = Thread.new do
            begin
              while r.gets
              end
            rescue IOError => e
              e
            end
          end
          Thread.pass until th.stop?

          r.close
          assert_same th, th.join(30), '"bad" reader timeout'
          assert_match(/stream closed/, th.value.message)
        end
      end
      sig_wr.write 'done'
      assert_same noex, noex.join(20), '"good" writer timeout'
      assert_equal 'done', noex.value ,'r63216'
    end
  end

  def test_select_leak
    # avoid malloc arena explosion from glibc and jemalloc:
    env = {
      'MALLOC_ARENA_MAX' => '1',
      'MALLOC_ARENA_TEST' => '1',
      'MALLOC_CONF' => 'narenas:1',
    }
    assert_no_memory_leak([env], <<-"end;", <<-"end;", rss: true, timeout: 60)
      r, w = IO.pipe
      rset = [r]
      wset = [w]
      exc = StandardError.new(-"select used to leak on exception")
      exc.set_backtrace([])
      Thread.new { IO.select(rset, wset, nil, 0) }.join
    end;
      th = Thread.new do
        Thread.handle_interrupt(StandardError => :on_blocking) do
          begin
            IO.select(rset, wset)
          rescue
            retry
          end while true
        end
      end
      50_000.times do
        Thread.pass until th.stop?
        th.raise(exc)
      end
      th.kill
      th.join
    end;
  end

  def test_external_encoding_index
    IO.pipe {|r, w|
      assert_raise(TypeError) {Marshal.dump(r)}
      assert_raise(TypeError) {Marshal.dump(w)}
    }
  end
end
