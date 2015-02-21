require 'test/unit'
require 'tempfile'
require "thread"
require_relative 'ut_eof'

class TestFile < Test::Unit::TestCase

  # I don't know Ruby's spec about "unlink-before-close" exactly.
  # This test asserts current behaviour.
  def test_unlink_before_close
    Dir.mktmpdir('rubytest-file') {|tmpdir|
      filename = tmpdir + '/' + File.basename(__FILE__) + ".#{$$}"
      w = File.open(filename, "w")
      w << "foo"
      w.close
      r = File.open(filename, "r")
      begin
        if /(mswin|bccwin|mingw|emx)/ =~ RUBY_PLATFORM
          assert_raise(Errno::EACCES) {File.unlink(filename)}
        else
          assert_nothing_raised {File.unlink(filename)}
        end
      ensure
        r.close
        File.unlink(filename) if File.exist?(filename)
      end
    }
  end

  include TestEOF
  def open_file(content)
    Tempfile.create("test-eof") {|f|
      f << content
      f.rewind
      yield f
    }
  end
  alias open_file_rw open_file

  include TestEOF::Seek

  def test_empty_file_bom
    bug6487 = '[ruby-core:45203]'
    Tempfile.create(__method__.to_s) {|f|
      assert_file.exist?(f.path)
      assert_nothing_raised(bug6487) {File.read(f.path, mode: 'r:utf-8')}
      assert_nothing_raised(bug6487) {File.read(f.path, mode: 'r:bom|utf-8')}
    }
  end

  def assert_bom(bytes, name)
    bug6487 = '[ruby-core:45203]'

    Tempfile.create(name.to_s) {|f|
      f.sync = true
      expected = ""
      result = nil
      bytes[0...-1].each do |x|
        f.write x
        f.write ' '
        f.pos -= 1
        expected << x
        assert_nothing_raised(bug6487) {result = File.read(f.path, mode: 'rb:bom|utf-8')}
        assert_equal("#{expected} ".force_encoding("utf-8"), result)
      end
      f.write bytes[-1]
      assert_nothing_raised(bug6487) {result = File.read(f.path, mode: 'rb:bom|utf-8')}
      assert_equal '', result, "valid bom"
    }
  end

  def test_bom_8
    assert_bom(["\xEF", "\xBB", "\xBF"], __method__)
  end

  def test_bom_16be
    assert_bom(["\xFE", "\xFF"], __method__)
  end

  def test_bom_16le
    assert_bom(["\xFF", "\xFE"], __method__)
  end

  def test_bom_32be
    assert_bom(["\0", "\0", "\xFE", "\xFF"], __method__)
  end

  def test_bom_32le
    assert_bom(["\xFF\xFE\0", "\0"], __method__)
  end

  def test_truncate_wbuf
    Tempfile.create("test-truncate") {|f|
      f.print "abc"
      f.truncate(0)
      f.print "def"
      f.flush
      assert_equal("\0\0\0def", File.read(f.path), "[ruby-dev:24191]")
    }
  end

  def test_truncate_rbuf
    Tempfile.create("test-truncate") {|f|
      f.puts "abc"
      f.puts "def"
      f.rewind
      assert_equal("abc\n", f.gets)
      f.truncate(3)
      assert_equal(nil, f.gets, "[ruby-dev:24197]")
    }
  end

  def test_truncate_beyond_eof
    Tempfile.create("test-truncate") {|f|
      f.print "abc"
      f.truncate 10
      assert_equal("\0" * 7, f.read(100), "[ruby-dev:24532]")
    }
  end

  def test_truncate_size
    Tempfile.create("test-truncate") do |f|
      q1 = Queue.new
      q2 = Queue.new

      th = Thread.new do
        data = ''
        64.times do |i|
          data << i.to_s
          f.rewind
          f.print data
          f.truncate(data.bytesize)
          q1.push data.bytesize
          q2.pop
        end
        q1.push nil
      end

      while size = q1.pop
        assert_equal size, File.size(f.path)
        assert_equal size, f.size
        q2.push true
      end
      th.join
    end
  end

  def test_read_all_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal("a", f.read, "mode = <#{mode}>")
      }
    end
  end

  def test_gets_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal("a", f.gets("a"), "mode = <#{mode}>")
      }
    end
  end

  def test_gets_para_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "\na"
        f.rewind
        assert_equal("a", f.gets(""), "mode = <#{mode}>")
      }
    end
  end

  def test_each_char_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        result = []
        f.each_char {|b| result << b }
        assert_equal([?a], result, "mode = <#{mode}>")
      }
    end
  end

  def test_each_byte_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        result = []
        f.each_byte {|b| result << b.chr }
        assert_equal([?a], result, "mode = <#{mode}>")
      }
    end
  end

  def test_getc_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal(?a, f.getc, "mode = <#{mode}>")
      }
    end
  end

  def test_getbyte_extended_file
    [nil, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal(?a, f.getbyte.chr, "mode = <#{mode}>")
      }
    end
  end

  def test_s_chown
    assert_nothing_raised { File.chown(-1, -1) }
    assert_nothing_raised { File.chown nil, nil }
  end

  def test_chown
    assert_nothing_raised {
      File.open(__FILE__) {|f| f.chown(-1, -1) }
    }
    assert_nothing_raised("[ruby-dev:27140]") {
      File.open(__FILE__) {|f| f.chown nil, nil }
    }
  end

  def test_uninitialized
    assert_raise(TypeError) { File::Stat.allocate.readable? }
    assert_nothing_raised { File::Stat.allocate.inspect }
  end

  def test_realpath
    Dir.mktmpdir('rubytest-realpath') {|tmpdir|
      realdir = File.realpath(tmpdir)
      tst = realdir + (File::SEPARATOR*3 + ".")
      assert_equal(realdir, File.realpath(tst))
      assert_equal(realdir, File.realpath(".", tst))
      if File::ALT_SEPARATOR
        bug2961 = '[ruby-core:28653]'
        assert_equal(realdir, File.realpath(realdir.tr(File::SEPARATOR, File::ALT_SEPARATOR)), bug2961)
      end
    }
  end

  def test_realdirpath
    Dir.mktmpdir('rubytest-realdirpath') {|tmpdir|
      realdir = File.realpath(tmpdir)
      tst = realdir + (File::SEPARATOR*3 + ".")
      assert_equal(realdir, File.realdirpath(tst))
      assert_equal(realdir, File.realdirpath(".", tst))
      assert_equal(File.join(realdir, "foo"), File.realdirpath("foo", tst))
    }
    begin
      result = File.realdirpath("bar", "//:/foo")
    rescue SystemCallError
    else
      if result.start_with?("//")
        assert_equal("//:/foo/bar", result)
      end
    end
  end

  def test_utime_with_minus_time_segv
    bug5596 = '[ruby-dev:44838]'
    assert_in_out_err([], <<-EOS, [bug5596], [])
      require "tempfile"
      t = Time.at(-1)
      begin
        Tempfile.create('test_utime_with_minus_time_segv') {|f|
          File.utime(t, t, f)
        }
      rescue
      end
      puts '#{bug5596}'
    EOS
  end

  def test_utime
    bug6385 = '[ruby-core:44776]'

    mod_time_contents = Time.at 1306527039

    file = Tempfile.new("utime")
    file.close
    path = file.path

    File.utime(File.atime(path), mod_time_contents, path)
    stats = File.stat(path)

    file.open
    file_mtime = file.mtime
    file.close(true)

    assert_equal(mod_time_contents, file_mtime, bug6385)
    assert_equal(mod_time_contents, stats.mtime, bug6385)
  end

  def test_stat
    tb = Process.clock_gettime(Process::CLOCK_REALTIME)
    Tempfile.create("stat") {|file|
      tb = (tb + Process.clock_gettime(Process::CLOCK_REALTIME)) / 2
      file.close
      path = file.path

      t0 = Process.clock_gettime(Process::CLOCK_REALTIME)
      File.write(path, "foo")
      sleep 2
      File.write(path, "bar")
      sleep 2
      File.chmod(0644, path)
      sleep 2
      File.read(path)

      delta = 1
      stat = File.stat(path)
      assert_in_delta tb,   stat.birthtime.to_f, delta
      assert_in_delta t0+2, stat.mtime.to_f, delta
      if stat.birthtime != stat.ctime
        assert_in_delta t0+4, stat.ctime.to_f, delta
      end
      unless /mswin|mingw/ =~ RUBY_PLATFORM
        # Windows delays updating atime
        assert_in_delta t0+6, stat.atime.to_f, delta
      end
    }
  rescue NotImplementedError
  end

  def test_chmod_m17n
    bug5671 = '[ruby-dev:44898]'
    Dir.mktmpdir('test-file-chmod-m17n-') do |tmpdir|
      file = File.join(tmpdir, "\u3042")
      File.open(file, 'w'){}
      assert_equal(File.chmod(0666, file), 1, bug5671)
    end
  end

  def test_file_open_permissions
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      tmp = File.join(tmpdir, 'x')
      File.open(tmp, :mode     => IO::RDWR | IO::CREAT | IO::BINARY,
                     :encoding => Encoding::ASCII_8BIT) do |x|

        assert_predicate(x, :autoclose?)
        assert_equal Encoding::ASCII_8BIT, x.external_encoding
        x.write 'hello'

        x.seek 0, IO::SEEK_SET

        assert_equal 'hello', x.read

      end
    end
  end

  def test_file_open_double_mode
    assert_raise_with_message(ArgumentError, 'mode specified twice') {
      File.open("a", 'w', :mode => 'rw+')
    }
  end

  def test_conflicting_encodings
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      tmp = File.join(tmpdir, 'x')
      File.open(tmp, 'wb', :encoding => Encoding::EUC_JP) do |x|
        assert_equal Encoding::EUC_JP, x.external_encoding
      end
    end
  end

  def test_untainted_path
    bug5374 = '[ruby-core:39745]'
    cwd = ("./"*40+".".taint).dup.untaint
    in_safe = proc {|safe| $SAFE = safe; File.stat(cwd)}
    assert_not_send([cwd, :tainted?])
    (0..1).each do |level|
      assert_nothing_raised(SecurityError, bug5374) {in_safe[level]}
    end
    def (s = Object.new).to_path; "".taint; end
    m = "\u{691c 67fb}"
    (c = Class.new(File)).singleton_class.class_eval {alias_method m, :stat}
    assert_raise_with_message(SecurityError, /#{m}/) {
      proc {$SAFE = 3; c.__send__(m, s)}.call
    }
  end

  if /(bcc|ms|cyg)win|mingw|emx/ =~ RUBY_PLATFORM
    def test_long_unc
      feature3399 = '[ruby-core:30623]'
      path = File.expand_path(__FILE__)
      path.sub!(%r'\A//', 'UNC/')
      assert_nothing_raised(Errno::ENOENT, feature3399) do
        File.stat("//?/#{path}")
      end
    end
  end

  def test_open_nul
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      path = File.join(tmpdir, "foo")
      assert_raise(ArgumentError) do
        open(path + "\0bar", "w") {}
      end
      assert_file.not_exist?(path)
    end
  end
end
