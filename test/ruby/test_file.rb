# frozen_string_literal: false
require 'test/unit'
require 'tempfile'
require "-test-/file"
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
    assert_bom(["\xFF", "\xFE\0\0"], __method__)
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
      q1 = Thread::Queue.new
      q2 = Thread::Queue.new

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
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal("a", f.read, "mode = <#{mode}>")
      }
    end
  end

  def test_gets_extended_file
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal("a", f.gets("a"), "mode = <#{mode}>")
      }
    end
  end

  def test_gets_para_extended_file
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
        assert_nil(f.getc)
        f.print "\na"
        f.rewind
        assert_equal("a", f.gets(""), "mode = <#{mode}>")
      }
    end
  end

  def test_each_char_extended_file
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
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
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
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
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
        assert_nil(f.getc)
        f.print "a"
        f.rewind
        assert_equal(?a, f.getc, "mode = <#{mode}>")
      }
    end
  end

  def test_getbyte_extended_file
    [{}, {:textmode=>true}, {:binmode=>true}].each do |mode|
      Tempfile.create("test-extended-file", **mode) {|f|
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
    Tempfile.create("test-chown") {|f|
      assert_nothing_raised {f.chown(-1, -1)}
      assert_nothing_raised("[ruby-dev:27140]") {f.chown(nil, nil)}
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
      assert_equal(realdir, Dir.chdir(realdir) {File.realpath(".")})
      realpath = File.join(realdir, "test")
      File.write(realpath, "")
      assert_equal(realpath, Dir.chdir(realdir) {File.realpath("test")})
      if File::ALT_SEPARATOR
        bug2961 = '[ruby-core:28653]'
        assert_equal(realdir, File.realpath(realdir.tr(File::SEPARATOR, File::ALT_SEPARATOR)), bug2961)
      end
    }
  end

  def test_realpath_encoding
    fsenc = Encoding.find("filesystem")
    nonascii = "\u{0391 0410 0531 10A0 05d0 2C00 3042}"
    tst = "A"
    nonascii.each_char {|c| tst << c.encode(fsenc) rescue nil}
    Dir.mktmpdir('rubytest-realpath') {|tmpdir|
      realdir = File.realpath(tmpdir)
      open(File.join(tmpdir, tst), "w") {}
      a = File.join(tmpdir, "x")
      begin
        File.symlink(tst, a)
      rescue Errno::EACCES, Errno::EPERM
        omit "need privilege"
      end
      assert_equal(File.join(realdir, tst), File.realpath(a))
      File.unlink(a)

      tst = "A" + nonascii
      open(File.join(tmpdir, tst), "w") {}
      File.symlink(tst, a)
      assert_equal(File.join(realdir, tst), File.realpath(a.encode("UTF-8")))
    }
  end

  def test_realpath_special_symlink
    IO.pipe do |r, w|
      if File.pipe?(path = "/dev/fd/#{r.fileno}")
        assert_file.identical?(File.realpath(path), path)
      end
    end
  end

  def test_realdirpath
    Dir.mktmpdir('rubytest-realdirpath') {|tmpdir|
      realdir = File.realpath(tmpdir)
      tst = realdir + (File::SEPARATOR*3 + ".")
      assert_equal(realdir, File.realdirpath(tst))
      assert_equal(realdir, File.realdirpath(".", tst))
      assert_equal(File.join(realdir, "foo"), File.realdirpath("foo", tst))
      assert_equal(realdir, Dir.chdir(realdir) {File.realdirpath(".")})
      assert_equal(File.join(realdir, "foo"), Dir.chdir(realdir) {File.realdirpath("foo")})
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

  def test_realdirpath_junction
    Dir.mktmpdir('rubytest-realpath') {|tmpdir|
      Dir.chdir(tmpdir) do
        Dir.mkdir('foo')
        omit "cannot run mklink" unless system('mklink /j bar foo > nul')
        assert_equal(File.realpath('foo'), File.realpath('bar'))
      end
    }
  end if /mswin|mingw/ =~ RUBY_PLATFORM

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

  def measure_time
    log = []
    30.times do
      t1 = Process.clock_gettime(Process::CLOCK_REALTIME)
      yield
      t2 = Process.clock_gettime(Process::CLOCK_REALTIME)
      log << (t2 - t1)
      return (t1 + t2) / 2 if t2 - t1 < 1
      sleep 1
    end
    omit "failed to setup; the machine is stupidly slow #{log.inspect}"
  end

  def test_stat
    btime = Process.clock_gettime(Process::CLOCK_REALTIME)
    Tempfile.create("stat") {|file|
      btime = (btime + Process.clock_gettime(Process::CLOCK_REALTIME)) / 2
      file.close
      path = file.path

      measure_time do
        File.write(path, "foo")
      end

      sleep 2

      mtime = measure_time do
        File.write(path, "bar")
      end

      sleep 2

      ctime = measure_time do
        File.chmod(0644, path)
      end

      sleep 2

      atime = measure_time do
        File.read(path)
      end

      delta = 1
      stat = File.stat(path)
      assert_in_delta btime, stat.birthtime.to_f, delta
      assert_in_delta mtime, stat.mtime.to_f, delta
      if stat.birthtime != stat.ctime
        assert_in_delta ctime, stat.ctime.to_f, delta
      end
      if /mswin|mingw/ !~ RUBY_PLATFORM && !Bug::File::Fs.noatime?(path)
        # Windows delays updating atime
        assert_in_delta atime, stat.atime.to_f, delta
      end
    }
  rescue NotImplementedError
  end

  def test_stat_inode
    assert_not_equal 0, File.stat(__FILE__).ino
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

  def test_file_share_delete
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      tmp = File.join(tmpdir, 'x')
      File.open(tmp, mode: IO::WRONLY | IO::CREAT | IO::BINARY | IO::SHARE_DELETE) do |f|
        assert_file.exist?(tmp)
        assert_nothing_raised do
          File.unlink(tmp)
        end
      end
      assert_file.not_exist?(tmp)
    end
  end

  def test_conflicting_encodings
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      tmp = File.join(tmpdir, 'x')
      File.open(tmp, 'wb', :encoding => Encoding::EUC_JP) do |x|
        assert_equal Encoding::EUC_JP, x.external_encoding
      end
    end
  end

  if /mswin|mingw/ =~ RUBY_PLATFORM
    def test_long_unc
      feature3399 = '[ruby-core:30623]'
      path = File.expand_path(__FILE__)
      path.sub!(%r'\A//', 'UNC/')
      assert_nothing_raised(Errno::ENOENT, feature3399) do
        File.stat("//?/#{path}")
      end
    end
  end

  def test_initialize
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      path = File.join(tmpdir, "foo")

      assert_raise(Errno::ENOENT) {File.new(path)}
      f = File.new(path, "w")
      f.write("FOO\n")
      f.close
      f = File.new(path)
      data = f.read
      f.close
      assert_equal("FOO\n", data)

      f = File.new(path, File::WRONLY)
      f.write("BAR\n")
      f.close
      f = File.new(path, File::RDONLY)
      data = f.read
      f.close
      assert_equal("BAR\n", data)

      data = File.open(path) {|file|
        File.new(file.fileno, mode: File::RDONLY, autoclose: false).read
      }
      assert_equal("BAR\n", data)

      data = File.open(path) {|file|
        File.new(file.fileno, File::RDONLY, autoclose: false).read
      }
      assert_equal("BAR\n", data)
    end
  end

  def test_file_open_newline_option
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      path = File.join(tmpdir, "foo")
      test = lambda do |newline|
        File.open(path, "wt", newline: newline) do |f|
          f.write "a\n"
          f.puts "b"
        end
        File.binread(path)
      end
      assert_equal("a\nb\n", test.(:lf))
      assert_equal("a\nb\n", test.(:universal))
      assert_equal("a\r\nb\r\n", test.(:crlf))
      assert_equal("a\rb\r", test.(:cr))

      test = lambda do |newline|
        File.open(path, "rt", newline: newline) do |f|
          f.read
        end
      end

      File.binwrite(path, "a\nb\n")
      assert_equal("a\nb\n", test.(:lf))
      assert_equal("a\nb\n", test.(:universal))
      assert_equal("a\nb\n", test.(:crlf))
      assert_equal("a\nb\n", test.(:cr))

      File.binwrite(path, "a\r\nb\r\n")
      assert_equal("a\r\nb\r\n", test.(:lf))
      assert_equal("a\nb\n", test.(:universal))
      # Work on both Windows and non-Windows
      assert_include(["a\r\nb\r\n", "a\nb\n"], test.(:crlf))
      assert_equal("a\r\nb\r\n", test.(:cr))

      File.binwrite(path, "a\rb\r")
      assert_equal("a\rb\r", test.(:lf))
      assert_equal("a\nb\n", test.(:universal))
      assert_equal("a\rb\r", test.(:crlf))
      assert_equal("a\rb\r", test.(:cr))
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

  def test_open_tempfile_path
    Dir.mktmpdir(__method__.to_s) do |tmpdir|
      begin
        io = File.open(tmpdir, File::RDWR | File::TMPFILE)
      rescue Errno::EINVAL
        omit 'O_TMPFILE not supported (EINVAL)'
      rescue Errno::EISDIR
        omit 'O_TMPFILE not supported (EISDIR)'
      rescue Errno::EOPNOTSUPP
        omit 'O_TMPFILE not supported (EOPNOTSUPP)'
      end

      io.write "foo"
      io.flush
      assert_equal 3, io.size
      assert_nil io.path
    ensure
      io&.close
    end
  end if File::Constants.const_defined?(:TMPFILE)

  def test_absolute_path?
    assert_file.absolute_path?(File.absolute_path(__FILE__))
    assert_file.absolute_path?("//foo/bar\\baz")
    assert_file.not_absolute_path?(File.basename(__FILE__))
    assert_file.not_absolute_path?("C:foo\\bar")
    assert_file.not_absolute_path?("~")
    assert_file.not_absolute_path?("~user")

    if /cygwin|mswin|mingw/ =~ RUBY_PLATFORM
      assert_file.absolute_path?("C:\\foo\\bar")
      assert_file.absolute_path?("C:/foo/bar")
    else
      assert_file.not_absolute_path?("C:\\foo\\bar")
      assert_file.not_absolute_path?("C:/foo/bar")
    end
    if /mswin|mingw/ =~ RUBY_PLATFORM
      assert_file.not_absolute_path?("/foo/bar\\baz")
    else
      assert_file.absolute_path?("/foo/bar\\baz")
    end
  end

  class NewlineConvTests < Test::Unit::TestCase
    TEST_STRING_WITH_CRLF = "line1\r\nline2\r\n".freeze
    TEST_STRING_WITH_LF = "line1\nline2\n".freeze

    def setup
      @tmpdir = Dir.mktmpdir(self.class.name)
      @read_path_with_crlf = File.join(@tmpdir, "read_path_with_crlf")
      File.binwrite(@read_path_with_crlf, TEST_STRING_WITH_CRLF)
      @read_path_with_lf = File.join(@tmpdir, "read_path_with_lf")
      File.binwrite(@read_path_with_lf, TEST_STRING_WITH_LF)
      @write_path = File.join(@tmpdir, "write_path")
      File.binwrite(@write_path, '')
    end

    def teardown
      FileUtils.rm_rf @tmpdir
    end

    def windows?
      /cygwin|mswin|mingw/ =~ RUBY_PLATFORM
    end

    def open_file_with(method, filename, mode)
      read_or_write = mode.include?('w') ? :write : :read
      binary_or_text = mode.include?('b') ? :binary : :text

      f = case method
      when :ruby_file_open
        File.open(filename, mode)
      when :c_rb_file_open
        Bug::File::NewlineConv.rb_file_open(filename, read_or_write, binary_or_text)
      when :c_rb_io_fdopen
        Bug::File::NewlineConv.rb_io_fdopen(filename, read_or_write, binary_or_text)
      else
        raise "Don't know how to open with #{method}"
      end

      begin
        yield f
      ensure
        f.close
      end
    end

    def assert_file_contents_has_lf(f)
      assert_equal TEST_STRING_WITH_LF, f.read
    end

    def assert_file_contents_has_crlf(f)
      assert_equal TEST_STRING_WITH_CRLF, f.read
    end

    def assert_file_contents_has_lf_on_windows(f)
      if windows?
        assert_file_contents_has_lf(f)
      else
        assert_file_contents_has_crlf(f)
      end
    end

    def assert_file_contents_has_crlf_on_windows(f)
      if windows?
        assert_file_contents_has_crlf(f)
      else
        assert_file_contents_has_lf(f)
      end
    end

    def test_ruby_file_open_text_mode_read_crlf
      open_file_with(:ruby_file_open, @read_path_with_crlf, 'r') { |f| assert_file_contents_has_lf_on_windows(f) }
    end

    def test_ruby_file_open_bin_mode_read_crlf
      open_file_with(:ruby_file_open, @read_path_with_crlf, 'rb') { |f| assert_file_contents_has_crlf(f) }
    end

    def test_ruby_file_open_text_mode_read_lf
      open_file_with(:ruby_file_open, @read_path_with_lf, 'r') { |f| assert_file_contents_has_lf(f) }
    end

    def test_ruby_file_open_bin_mode_read_lf
      open_file_with(:ruby_file_open, @read_path_with_lf, 'rb') { |f| assert_file_contents_has_lf(f) }
    end

    def test_ruby_file_open_text_mode_read_crlf_with_utf8_encoding
      open_file_with(:ruby_file_open, @read_path_with_crlf, 'r') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf_on_windows(f)
      end
    end

    def test_ruby_file_open_bin_mode_read_crlf_with_utf8_encoding
      open_file_with(:ruby_file_open, @read_path_with_crlf, 'rb') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_crlf(f)
      end
    end

    def test_ruby_file_open_text_mode_read_lf_with_utf8_encoding
      open_file_with(:ruby_file_open, @read_path_with_lf, 'r') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf(f)
      end
    end

    def test_ruby_file_open_bin_mode_read_lf_with_utf8_encoding
      open_file_with(:ruby_file_open, @read_path_with_lf, 'rb') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf(f)
      end
    end

    def test_ruby_file_open_text_mode_write_lf
      open_file_with(:ruby_file_open, @write_path, 'w') { |f| f.write TEST_STRING_WITH_LF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_crlf_on_windows(f) }
    end

    def test_ruby_file_open_bin_mode_write_lf
      open_file_with(:ruby_file_open, @write_path, 'wb') { |f| f.write TEST_STRING_WITH_LF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_lf(f) }
    end

    def test_ruby_file_open_bin_mode_write_crlf
      open_file_with(:ruby_file_open, @write_path, 'wb') { |f| f.write TEST_STRING_WITH_CRLF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_crlf(f) }
    end

    def test_c_rb_file_open_text_mode_read_crlf
      open_file_with(:c_rb_file_open, @read_path_with_crlf, 'r') { |f| assert_file_contents_has_lf_on_windows(f) }
    end

    def test_c_rb_file_open_bin_mode_read_crlf
      open_file_with(:c_rb_file_open, @read_path_with_crlf, 'rb') { |f| assert_file_contents_has_crlf(f) }
    end

    def test_c_rb_file_open_text_mode_read_lf
      open_file_with(:c_rb_file_open, @read_path_with_lf, 'r') { |f| assert_file_contents_has_lf(f) }
    end

    def test_c_rb_file_open_bin_mode_read_lf
      open_file_with(:c_rb_file_open, @read_path_with_lf, 'rb') { |f| assert_file_contents_has_lf(f) }
    end

    def test_c_rb_file_open_text_mode_write_lf
      open_file_with(:c_rb_file_open, @write_path, 'w') { |f| f.write TEST_STRING_WITH_LF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_crlf_on_windows(f) }
    end

    def test_c_rb_file_open_bin_mode_write_lf
      open_file_with(:c_rb_file_open, @write_path, 'wb') { |f| f.write TEST_STRING_WITH_LF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_lf(f) }
    end

    def test_c_rb_file_open_bin_mode_write_crlf
      open_file_with(:c_rb_file_open, @write_path, 'wb') { |f| f.write TEST_STRING_WITH_CRLF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_crlf(f) }
    end

    def test_c_rb_file_open_text_mode_read_crlf_with_utf8_encoding
      open_file_with(:c_rb_file_open, @read_path_with_crlf, 'r') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf_on_windows(f)
      end
    end

    def test_c_rb_file_open_bin_mode_read_crlf_with_utf8_encoding
      open_file_with(:c_rb_file_open, @read_path_with_crlf, 'rb') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_crlf(f)
      end
    end

    def test_c_rb_file_open_text_mode_read_lf_with_utf8_encoding
      open_file_with(:c_rb_file_open, @read_path_with_lf, 'r') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf(f)
      end
    end

    def test_c_rb_file_open_bin_mode_read_lf_with_utf8_encoding
      open_file_with(:c_rb_file_open, @read_path_with_lf, 'rb') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf(f)
      end
    end

    def test_c_rb_io_fdopen_text_mode_read_crlf
      open_file_with(:c_rb_io_fdopen, @read_path_with_crlf, 'r') { |f| assert_file_contents_has_lf_on_windows(f) }
    end

    def test_c_rb_io_fdopen_bin_mode_read_crlf
      open_file_with(:c_rb_io_fdopen, @read_path_with_crlf, 'rb') { |f| assert_file_contents_has_crlf(f) }
    end

    def test_c_rb_io_fdopen_text_mode_read_lf
      open_file_with(:c_rb_io_fdopen, @read_path_with_lf, 'r') { |f| assert_file_contents_has_lf(f) }
    end

    def test_c_rb_io_fdopen_bin_mode_read_lf
      open_file_with(:c_rb_io_fdopen, @read_path_with_lf, 'rb') { |f| assert_file_contents_has_lf(f) }
    end

    def test_c_rb_io_fdopen_text_mode_write_lf
      open_file_with(:c_rb_io_fdopen, @write_path, 'w') { |f| f.write TEST_STRING_WITH_LF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_crlf_on_windows(f) }
    end

    def test_c_rb_io_fdopen_bin_mode_write_lf
      open_file_with(:c_rb_io_fdopen, @write_path, 'wb') { |f| f.write TEST_STRING_WITH_LF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_lf(f) }
    end

    def test_c_rb_io_fdopen_bin_mode_write_crlf
      open_file_with(:c_rb_io_fdopen, @write_path, 'wb') { |f| f.write TEST_STRING_WITH_CRLF }
      File.open(@write_path, 'rb') { |f| assert_file_contents_has_crlf(f) }
    end

    def test_c_rb_io_fdopen_text_mode_read_crlf_with_utf8_encoding
      open_file_with(:c_rb_io_fdopen, @read_path_with_crlf, 'r') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf_on_windows(f)
      end
    end

    def test_c_rb_io_fdopen_bin_mode_read_crlf_with_utf8_encoding
      open_file_with(:c_rb_io_fdopen, @read_path_with_crlf, 'rb') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_crlf(f)
      end
    end

    def test_c_rb_io_fdopen_text_mode_read_lf_with_utf8_encoding
      open_file_with(:c_rb_io_fdopen, @read_path_with_lf, 'r') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf(f)
      end
    end

    def test_c_rb_io_fdopen_bin_mode_read_lf_with_utf8_encoding
      open_file_with(:c_rb_io_fdopen, @read_path_with_lf, 'rb') do |f|
        f.set_encoding Encoding::UTF_8, '-'
        assert_file_contents_has_lf(f)
      end
    end
  end
end
