require "test/unit"
require "fileutils"
require "tmpdir"
require_relative "envutil"

class TestFileExhaustive < Test::Unit::TestCase
  DRIVE = Dir.pwd[%r'\A(?:[a-z]:|//[^/]+/[^/]+)'i]

  def assert_incompatible_encoding
    d = "\u{3042}\u{3044}".encode("utf-16le")
    assert_raise(Encoding::CompatibilityError) {yield d}
    m = Class.new {define_method(:to_path) {d}}
    assert_raise(Encoding::CompatibilityError) {yield m.new}
  end

  def setup
    @dir = Dir.mktmpdir("rubytest-file")
    @rootdir = "#{DRIVE}/"
    File.chown(-1, Process.gid, @dir)
    @file = make_tmp_filename("file")
    @zerofile = make_tmp_filename("zerofile")
    @nofile = make_tmp_filename("nofile")
    @symlinkfile = make_tmp_filename("symlinkfile")
    @hardlinkfile = make_tmp_filename("hardlinkfile")
    make_file("foo", @file)
    make_file("", @zerofile)
    @time = Time.now
    begin
      File.symlink(@file, @symlinkfile)
    rescue NotImplementedError
      @symlinkfile = nil
    end
    begin
      File.link(@file, @hardlinkfile)
    rescue NotImplementedError, Errno::EINVAL	# EINVAL for Windows Vista
      @hardlinkfile = nil
    end
  end

  def teardown
    GC.start
    FileUtils.remove_entry_secure @dir
  end

  def make_file(content, file = @file)
    open(file, "w") {|fh| fh << content }
  end

  def make_tmp_filename(prefix)
    @hardlinkfile = @dir + "/" + prefix + File.basename(__FILE__) + ".#{$$}.test"
  end

  def test_path
    file = @file

    assert_equal(file, File.open(file) {|f| f.path})
    assert_equal(file, File.path(file))
    o = Object.new
    class << o; self; end.class_eval do
      define_method(:to_path) { file }
    end
    assert_equal(file, File.path(o))
  end

  def assert_integer(n)
    assert(n.is_a?(Integer), n.inspect + " is not Fixnum.")
  end

  def assert_integer_or_nil(n)
    assert(n.is_a?(Integer) || n.equal?(nil), n.inspect + " is neither Fixnum nor nil.")
  end

  def test_stat
    sleep(@time - Time.now + 1.1)
    make_file("foo", @file + "2")
    fs1, fs2 = File.stat(@file), File.stat(@file + "2")
    assert_nothing_raised do
      assert_equal(0, fs1 <=> fs1)
      assert_equal(-1, fs1 <=> fs2)
      assert_equal(1, fs2 <=> fs1)
      assert_nil(fs1 <=> nil)
      assert_integer(fs1.dev)
      assert_integer_or_nil(fs1.rdev)
      assert_integer_or_nil(fs1.dev_major)
      assert_integer_or_nil(fs1.dev_minor)
      assert_integer_or_nil(fs1.rdev_major)
      assert_integer_or_nil(fs1.rdev_minor)
      assert_integer(fs1.ino)
      assert_integer(fs1.mode)
      unless /emx|mswin|mingw/ =~ RUBY_PLATFORM
        # on Windows, nlink is always 1. but this behavior will be changed
        # in the future.
        assert_equal(@hardlinkfile ? 2 : 1, fs1.nlink)
      end
      assert_integer(fs1.uid)
      assert_integer(fs1.gid)
      assert_equal(3, fs1.size)
      assert_integer_or_nil(fs1.blksize)
      assert_integer_or_nil(fs1.blocks)
      assert_kind_of(Time, fs1.atime)
      assert_kind_of(Time, fs1.mtime)
      assert_kind_of(Time, fs1.ctime)
      assert_kind_of(String, fs1.inspect)
    end
    assert_raise(Errno::ENOENT) { File.stat(@nofile) }
    assert_kind_of(File::Stat, File.open(@file) {|f| f.stat})
    assert_raise(Errno::ENOENT) { File.lstat(@nofile) }
    assert_kind_of(File::Stat, File.open(@file) {|f| f.lstat})
  end

  def test_stat_drive_root
    assert_nothing_raised { File.stat(DRIVE + "/") }
    assert_nothing_raised { File.stat(DRIVE + "/.") }
    assert_nothing_raised { File.stat(DRIVE + "/..") }
    assert_raise(Errno::ENOENT) { File.stat(DRIVE + "/...") }
    # want to test the root of empty drive, but there is no method to test it...
  end if DRIVE

  def test_stat_dotted_prefix
    Dir.mktmpdir do |dir|
      prefix = File.join(dir, "...a")
      Dir.mkdir(prefix)
      assert_file.exist?(prefix)

      assert_nothing_raised { File.stat(prefix) }

      Dir.chdir(dir) do
        assert_nothing_raised { File.stat(File.basename(prefix)) }
      end
    end
  end if /mswin|mingw|cygwin/ =~ RUBY_PLATFORM

  def test_directory_p
    assert(File.directory?(@dir))
    assert(!(File.directory?(@dir+"/...")))
    assert(!(File.directory?(@file)))
    assert(!(File.directory?(@nofile)))
  end

  def test_pipe_p ## xxx
    assert(!(File.pipe?(@dir)))
    assert(!(File.pipe?(@file)))
    assert(!(File.pipe?(@nofile)))
  end

  def test_symlink_p
    assert(!(File.symlink?(@dir)))
    assert(!(File.symlink?(@file)))
    assert(File.symlink?(@symlinkfile)) if @symlinkfile
    assert(!(File.symlink?(@hardlinkfile))) if @hardlinkfile
    assert(!(File.symlink?(@nofile)))
  end

  def test_socket_p ## xxx
    assert(!(File.socket?(@dir)))
    assert(!(File.socket?(@file)))
    assert(!(File.socket?(@nofile)))
  end

  def test_blockdev_p ## xxx
    assert(!(File.blockdev?(@dir)))
    assert(!(File.blockdev?(@file)))
    assert(!(File.blockdev?(@nofile)))
  end

  def test_chardev_p ## xxx
    assert(!(File.chardev?(@dir)))
    assert(!(File.chardev?(@file)))
    assert(!(File.chardev?(@nofile)))
  end

  def test_exist_p
    assert_file.exist?(@dir)
    assert_file.exist?(@file)
    assert_file.not_exist?(@nofile)
  end

  def test_readable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0200, @file)
    assert(!(File.readable?(@file)))
    File.chmod(0600, @file)
    assert(File.readable?(@file))
    assert(!(File.readable?(@nofile)))
  end

  def test_readable_real_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0200, @file)
    assert(!(File.readable_real?(@file)))
    File.chmod(0600, @file)
    assert(File.readable_real?(@file))
    assert(!(File.readable_real?(@nofile)))
  end

  def test_world_readable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0006, @file)
    assert(File.world_readable?(@file))
    File.chmod(0060, @file)
    assert(!(File.world_readable?(@file)))
    File.chmod(0600, @file)
    assert(!(File.world_readable?(@file)))
    assert(!(File.world_readable?(@nofile)))
  end

  def test_writable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0400, @file)
    assert(!(File.writable?(@file)))
    File.chmod(0600, @file)
    assert(File.writable?(@file))
    assert(!(File.writable?(@nofile)))
  end

  def test_writable_real_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0400, @file)
    assert(!(File.writable_real?(@file)))
    File.chmod(0600, @file)
    assert(File.writable_real?(@file))
    assert(!(File.writable_real?(@nofile)))
  end

  def test_world_writable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0006, @file)
    assert(File.world_writable?(@file))
    File.chmod(0060, @file)
    assert(!(File.world_writable?(@file)))
    File.chmod(0600, @file)
    assert(!(File.world_writable?(@file)))
    assert(!(File.world_writable?(@nofile)))
  end

  def test_executable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0100, @file)
    assert(File.executable?(@file))
    File.chmod(0600, @file)
    assert(!(File.executable?(@file)))
    assert(!(File.executable?(@nofile)))
  end

  def test_executable_real_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0100, @file)
    assert(File.executable_real?(@file))
    File.chmod(0600, @file)
    assert(!(File.executable_real?(@file)))
    assert(!(File.executable_real?(@nofile)))
  end

  def test_file_p
    assert(!(File.file?(@dir)))
    assert(File.file?(@file))
    assert(!(File.file?(@nofile)))
  end

  def test_zero_p
    assert_nothing_raised { File.zero?(@dir) }
    assert(!(File.zero?(@file)))
    assert(File.zero?(@zerofile))
    assert(!(File.zero?(@nofile)))
  end

  def test_size_p
    assert_nothing_raised { File.size?(@dir) }
    assert_equal(3, File.size?(@file))
    assert(!(File.size?(@zerofile)))
    assert(!(File.size?(@nofile)))
  end

  def test_owned_p ## xxx
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    assert(File.owned?(@file))
    assert(File.grpowned?(@file))
  end

  def test_suid_sgid_sticky ## xxx
    assert(!(File.setuid?(@file)))
    assert(!(File.setgid?(@file)))
    assert(!(File.sticky?(@file)))
  end

  def test_identical_p
    assert(File.identical?(@file, @file))
    assert(!(File.identical?(@file, @zerofile)))
    assert(!(File.identical?(@file, @nofile)))
    assert(!(File.identical?(@nofile, @file)))
  end

  def test_s_size
    assert_integer(File.size(@dir))
    assert_equal(3, File.size(@file))
    assert_equal(0, File.size(@zerofile))
    assert_raise(Errno::ENOENT) { File.size(@nofile) }
  end

  def test_ftype
    assert_equal("directory", File.ftype(@dir))
    assert_equal("file", File.ftype(@file))
    assert_equal("link", File.ftype(@symlinkfile)) if @symlinkfile
    assert_equal("file", File.ftype(@hardlinkfile)) if @hardlinkfile
    assert_raise(Errno::ENOENT) { File.ftype(@nofile) }
  end

  def test_atime
    t1 = File.atime(@file)
    t2 = File.open(@file) {|f| f.atime}
    assert_kind_of(Time, t1)
    assert_kind_of(Time, t2)
    assert_equal(t1, t2)
    assert_raise(Errno::ENOENT) { File.atime(@nofile) }
  end

  def test_mtime
    t1 = File.mtime(@file)
    t2 = File.open(@file) {|f| f.mtime}
    assert_kind_of(Time, t1)
    assert_kind_of(Time, t2)
    assert_equal(t1, t2)
    assert_raise(Errno::ENOENT) { File.mtime(@nofile) }
  end

  def test_ctime
    t1 = File.ctime(@file)
    t2 = File.open(@file) {|f| f.ctime}
    assert_kind_of(Time, t1)
    assert_kind_of(Time, t2)
    assert_equal(t1, t2)
    assert_raise(Errno::ENOENT) { File.ctime(@nofile) }
  end

  def test_chmod
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    assert_equal(1, File.chmod(0444, @file))
    assert_equal(0444, File.stat(@file).mode % 01000)
    assert_equal(0, File.open(@file) {|f| f.chmod(0222)})
    assert_equal(0222, File.stat(@file).mode % 01000)
    File.chmod(0600, @file)
    assert_raise(Errno::ENOENT) { File.chmod(0600, @nofile) }
  end

  def test_lchmod
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    assert_equal(1, File.lchmod(0444, @file))
    assert_equal(0444, File.stat(@file).mode % 01000)
    File.lchmod(0600, @file)
    assert_raise(Errno::ENOENT) { File.lchmod(0600, @nofile) }
  rescue NotImplementedError
  end

  def test_chown ## xxx
  end

  def test_lchown ## xxx
  end

  def test_symlink
    return unless @symlinkfile
    assert_equal("link", File.ftype(@symlinkfile))
    assert_raise(Errno::EEXIST) { File.symlink(@file, @file) }
  end

  def test_utime
    t = Time.local(2000)
    File.utime(t + 1, t + 2, @zerofile)
    assert_equal(t + 1, File.atime(@zerofile))
    assert_equal(t + 2, File.mtime(@zerofile))
  end

  def test_hardlink
    return unless @hardlinkfile
    assert_equal("file", File.ftype(@hardlinkfile))
    assert_raise(Errno::EEXIST) { File.link(@file, @file) }
  end

  def test_readlink
    return unless @symlinkfile
    assert_equal(@file, File.readlink(@symlinkfile))
    assert_raise(Errno::EINVAL) { File.readlink(@file) }
    assert_raise(Errno::ENOENT) { File.readlink(@nofile) }
    if fs = Encoding.find("filesystem")
      assert_equal(fs, File.readlink(@symlinkfile).encoding)
    end
  rescue NotImplementedError
  end

  def test_readlink_long_path
    return unless @symlinkfile
    bug9157 = '[ruby-core:58592] [Bug #9157]'
    assert_separately(["-", @symlinkfile, bug9157], <<-"end;")
      symlinkfile, bug9157 = *ARGV
      100.step(1000, 100) do |n|
        File.unlink(symlinkfile)
        link = "foo"*n
        begin
          File.symlink(link, symlinkfile)
        rescue Errno::ENAMETOOLONG
          break
        end
        assert_equal(link, File.readlink(symlinkfile), bug9157)
      end
    end;
  end

  def test_unlink
    assert_equal(1, File.unlink(@file))
    make_file("foo", @file)
    assert_raise(Errno::ENOENT) { File.unlink(@nofile) }
  end

  def test_rename
    assert_equal(0, File.rename(@file, @nofile))
    assert_file.not_exist?(@file)
    assert_file.exist?(@nofile)
    assert_equal(0, File.rename(@nofile, @file))
    assert_raise(Errno::ENOENT) { File.rename(@nofile, @file) }
  end

  def test_umask
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    prev = File.umask(0777)
    assert_equal(0777, File.umask)
    open(@nofile, "w") { }
    assert_equal(0, File.stat(@nofile).mode % 01000)
    File.unlink(@nofile)
    assert_equal(0777, File.umask(prev))
    assert_raise(ArgumentError) { File.umask(0, 1, 2) }
  end

  def test_expand_path
    assert_equal(@file, File.expand_path(File.basename(@file), File.dirname(@file)))
    if /cygwin|mingw|mswin|bccwin/ =~ RUBY_PLATFORM
      assert_equal(@file, File.expand_path(@file + " "))
      assert_equal(@file, File.expand_path(@file + "."))
      assert_equal(@file, File.expand_path(@file + "::$DATA"))
      assert_match(/\Ac:\//i, File.expand_path('c:'), '[ruby-core:31591]')
      assert_match(/\Ac:\//i, File.expand_path('c:foo', 'd:/bar'))
      assert_match(%r'\Ac:/bar/foo\z'i, File.expand_path('c:foo', 'c:/bar'))
    end
    if DRIVE
      assert_match(%r"\Az:/foo\z"i, File.expand_path('/foo', "z:/bar"))
      assert_match(%r"\A//host/share/foo\z"i, File.expand_path('/foo', "//host/share/bar"))
      assert_match(%r"\A#{DRIVE}/foo\z"i, File.expand_path('/foo'))
    else
      assert_equal("/foo", File.expand_path('/foo'))
    end
  end

  def test_expand_path_encoding
    drive = (DRIVE ? 'C:' : '')
    if Encoding.find("filesystem") == Encoding::CP1251
      a = "#{drive}/\u3042\u3044\u3046\u3048\u304a".encode("cp932")
    else
      a = "#{drive}/\u043f\u0440\u0438\u0432\u0435\u0442".encode("cp1251")
    end
    assert_equal(a, File.expand_path(a))
    a = "#{drive}/\225\\\\"
    if File::ALT_SEPARATOR == '\\'
      [%W"cp437 #{drive}/\225", %W"cp932 #{drive}/\225\\"]
    else
      [["cp437", a], ["cp932", a]]
    end.each do |cp, expected|
      assert_equal(expected.force_encoding(cp), File.expand_path(a.dup.force_encoding(cp)), cp)
    end

    path = "\u3042\u3044\u3046\u3048\u304a".encode("EUC-JP")
    assert_equal("#{Dir.pwd}/#{path}".encode("CP932"), File.expand_path(path).encode("CP932"))

    path = "\u3042\u3044\u3046\u3048\u304a".encode("CP51932")
    assert_equal("#{Dir.pwd}/#{path}", File.expand_path(path))

    assert_incompatible_encoding {|d| File.expand_path(d)}
  end

  def test_expand_path_encoding_filesystem
    home = ENV["HOME"]
    ENV["HOME"] = "#{DRIVE}/UserHome"

    path = "~".encode("US-ASCII")
    dir = "C:/".encode("IBM437")
    fs = Encoding.find("filesystem")

    assert_equal fs, File.expand_path(path).encoding
    assert_equal fs, File.expand_path(path, dir).encoding
  ensure
    ENV["HOME"] = home
  end

  UnknownUserHome = "~foo_bar_baz_unknown_user_wahaha".freeze

  def test_expand_path_home
    assert_kind_of(String, File.expand_path("~")) if ENV["HOME"]
    assert_raise(ArgumentError) { File.expand_path(UnknownUserHome) }
    assert_raise(ArgumentError) { File.expand_path(UnknownUserHome, "/") }
    begin
      bug3630 = '[ruby-core:31537]'
      home = ENV["HOME"]
      home_drive = ENV["HOMEDRIVE"]
      home_path = ENV["HOMEPATH"]
      user_profile = ENV["USERPROFILE"]
      ENV["HOME"] = nil
      ENV["HOMEDRIVE"] = nil
      ENV["HOMEPATH"] = nil
      ENV["USERPROFILE"] = nil
      assert_raise(ArgumentError) { File.expand_path("~") }
      ENV["HOME"] = "~"
      assert_raise(ArgumentError, bug3630) { File.expand_path("~") }
      ENV["HOME"] = "."
      assert_raise(ArgumentError, bug3630) { File.expand_path("~") }
    ensure
      ENV["HOME"] = home
      ENV["HOMEDRIVE"] = home_drive
      ENV["HOMEPATH"] = home_path
      ENV["USERPROFILE"] = user_profile
    end
  end

  def test_expand_path_home_dir_string
    home = ENV["HOME"]
    new_home = "#{DRIVE}/UserHome"
    ENV["HOME"] = new_home
    bug8034 = "[ruby-core:53168]"

    assert_equal File.join(new_home, "foo"), File.expand_path("foo", "~"), bug8034
    assert_equal File.join(new_home, "bar", "foo"), File.expand_path("foo", "~/bar"), bug8034

    assert_raise(ArgumentError) { File.expand_path(".", UnknownUserHome) }
    assert_nothing_raised(ArgumentError) { File.expand_path("#{DRIVE}/", UnknownUserHome) }
  ensure
    ENV["HOME"] = home
  end

  if /mswin|mingw/ =~ RUBY_PLATFORM
    def test_expand_path_home_memory_leak_in_path
      assert_no_memory_leak_at_expand_path_home('', 'in path')
    end

    def test_expand_path_home_memory_leak_in_base
      assert_no_memory_leak_at_expand_path_home('".",', 'in base')
    end

    def assert_no_memory_leak_at_expand_path_home(arg, message)
      prep = 'ENV["HOME"] = "foo"*100'
      assert_no_memory_leak([], prep, <<-TRY, "memory leaked at non-absolute home #{message}")
      10000.times do
        begin
          File.expand_path(#{arg}"~/a")
        rescue ArgumentError => e
          next
        ensure
          abort("ArgumentError (non-absolute home) expected") unless e
        end
      end
      GC.start
      TRY
    end
  end


  def test_expand_path_remove_trailing_alternative_data
    assert_equal File.join(@rootdir, "aaa"), File.expand_path("#{@rootdir}/aaa::$DATA")
    assert_equal File.join(@rootdir, "aa:a"), File.expand_path("#{@rootdir}/aa:a:$DATA")
    assert_equal File.join(@rootdir, "aaa:$DATA"), File.expand_path("#{@rootdir}/aaa:$DATA")
  end if DRIVE

  def test_expand_path_resolve_empty_string_current_directory
    assert_equal(Dir.pwd, File.expand_path(""))
  end

  def test_expand_path_resolve_dot_current_directory
    assert_equal(Dir.pwd, File.expand_path("."))
  end

  def test_expand_path_resolve_file_name_relative_current_directory
    assert_equal(File.join(Dir.pwd, "foo"), File.expand_path("foo"))
  end

  def test_ignore_nil_dir_string
    assert_equal(File.join(Dir.pwd, "foo"), File.expand_path("foo", nil))
  end

  def test_expand_path_resolve_file_name_and_dir_string_relative
    assert_equal(File.join(Dir.pwd, "bar", "foo"),
      File.expand_path("foo", "bar"))
  end

  def test_expand_path_cleanup_dots_file_name
    bug = "[ruby-talk:18512]"

    assert_equal(File.join(Dir.pwd, ".a"), File.expand_path(".a"), bug)
    assert_equal(File.join(Dir.pwd, "..a"), File.expand_path("..a"), bug)

    if DRIVE
      # cleanup dots only on Windows
      assert_equal(File.join(Dir.pwd, "a"), File.expand_path("a."), bug)
      assert_equal(File.join(Dir.pwd, "a"), File.expand_path("a.."), bug)
    else
      assert_equal(File.join(Dir.pwd, "a."), File.expand_path("a."), bug)
      assert_equal(File.join(Dir.pwd, "a.."), File.expand_path("a.."), bug)
    end
  end

  def test_expand_path_converts_a_pathname_to_an_absolute_pathname_using_a_complete_path
    assert_equal(@dir, File.expand_path("", "#{@dir}"))
    assert_equal(File.join(@dir, "a"), File.expand_path("a", "#{@dir}"))
    assert_equal(File.join(@dir, "a"), File.expand_path("../a", "#{@dir}/xxx"))
    assert_equal(@rootdir, File.expand_path(".", "#{@rootdir}"))
  end

  def test_expand_path_ignores_supplied_dir_if_path_contains_a_drive_letter
    assert_equal(@rootdir, File.expand_path(@rootdir, "D:/"))
  end if DRIVE

  def test_expand_path_removes_trailing_slashes_from_absolute_path
    assert_equal(File.join(@rootdir, "foo"), File.expand_path("#{@rootdir}foo/"))
    assert_equal(File.join(@rootdir, "foo.rb"), File.expand_path("#{@rootdir}foo.rb/"))
  end

  def test_expand_path_removes_trailing_spaces_from_absolute_path
    assert_equal(File.join(@rootdir, "a"), File.expand_path("#{@rootdir}a "))
  end if DRIVE

  def test_expand_path_converts_a_pathname_which_starts_with_a_slash_using_dir_s_drive
    assert_match(%r"\Az:/foo\z"i, File.expand_path('/foo', "z:/bar"))
  end if DRIVE

  def test_expand_path_converts_a_pathname_which_starts_with_a_slash_and_unc_pathname
    assert_equal("//foo", File.expand_path('//foo', "//bar"))
    assert_equal("//bar/foo", File.expand_path('/foo', "//bar"))
    assert_equal("//foo", File.expand_path('//foo', "/bar"))
  end if DRIVE

  def test_expand_path_converts_a_dot_with_unc_dir
    assert_equal("//", File.expand_path('.', "//"))
  end

  def test_expand_path_preserves_unc_path_root
    assert_equal("//", File.expand_path("//"))
    assert_equal("//", File.expand_path("//."))
    assert_equal("//", File.expand_path("//.."))
  end

  def test_expand_path_converts_a_pathname_which_starts_with_a_slash_using_host_share
    assert_match(%r"\A//host/share/foo\z"i, File.expand_path('/foo', "//host/share/bar"))
  end if DRIVE

  def test_expand_path_converts_a_pathname_which_starts_with_a_slash_using_a_current_drive
    assert_match(%r"\A#{DRIVE}/foo\z"i, File.expand_path('/foo'))
  end

  def test_expand_path_returns_tainted_strings_or_not
    assert_equal(true, File.expand_path('foo').tainted?)
    assert_equal(true, File.expand_path('foo'.taint).tainted?)
    assert_equal(true, File.expand_path('/foo'.taint).tainted?)
    assert_equal(true, File.expand_path('foo', 'bar').tainted?)
    assert_equal(true, File.expand_path('foo', '/bar'.taint).tainted?)
    assert_equal(true, File.expand_path('foo'.taint, '/bar').tainted?)
    assert_equal(true, File.expand_path('~').tainted?) if ENV["HOME"]

    if DRIVE
      assert_equal(true, File.expand_path('/foo').tainted?)
      assert_equal(false, File.expand_path('//foo').tainted?)
      assert_equal(true, File.expand_path('C:/foo'.taint).tainted?)
      assert_equal(false, File.expand_path('C:/foo').tainted?)
      assert_equal(true, File.expand_path('foo', '/bar').tainted?)
      assert_equal(true, File.expand_path('foo', 'C:/bar'.taint).tainted?)
      assert_equal(true, File.expand_path('foo'.taint, 'C:/bar').tainted?)
      assert_equal(false, File.expand_path('foo', 'C:/bar').tainted?)
      assert_equal(false, File.expand_path('C:/foo/../bar').tainted?)
      assert_equal(false, File.expand_path('foo', '//bar').tainted?)
    else
      assert_equal(false, File.expand_path('/foo').tainted?)
      assert_equal(false, File.expand_path('foo', '/bar').tainted?)
    end
  end

  def test_expand_path_converts_a_pathname_to_an_absolute_pathname_using_home_as_base
    old_home = ENV["HOME"]
    home = ENV["HOME"] = "#{DRIVE}/UserHome"
    assert_equal(home, File.expand_path("~"))
    assert_equal(home, File.expand_path("~", "C:/FooBar"))
    assert_equal(File.join(home, "a"), File.expand_path("~/a", "C:/FooBar"))
  ensure
    ENV["HOME"] = old_home
  end

  def test_expand_path_converts_a_pathname_to_an_absolute_pathname_using_unc_home
    old_home = ENV["HOME"]
    unc_home = ENV["HOME"] = "//UserHome"
    assert_equal(unc_home, File.expand_path("~"))
  ensure
    ENV["HOME"] = old_home
  end if DRIVE

  def test_expand_path_does_not_modify_a_home_string_argument
    old_home = ENV["HOME"]
    home = ENV["HOME"] = "#{DRIVE}/UserHome"
    str = "~/a"
    assert_equal("#{home}/a", File.expand_path(str))
    assert_equal("~/a", str)
  ensure
    ENV["HOME"] = old_home
  end

  def test_expand_path_raises_argument_error_for_any_supplied_username
    bug = '[ruby-core:39597]'
    assert_raise(ArgumentError, bug) { File.expand_path("~anything") }
  end if DRIVE

  def test_expand_path_raises_a_type_error_if_not_passed_a_string_type
    assert_raise(TypeError) { File.expand_path(1) }
    assert_raise(TypeError) { File.expand_path(nil) }
    assert_raise(TypeError) { File.expand_path(true) }
  end

  def test_expand_path_expands_dot_dir
    assert_equal("#{DRIVE}/dir", File.expand_path("#{DRIVE}/./dir"))
  end

  def test_expand_path_does_not_expand_wildcards
    assert_equal("#{DRIVE}/*", File.expand_path("./*", "#{DRIVE}/"))
    assert_equal("#{Dir.pwd}/*", File.expand_path("./*", Dir.pwd))
    assert_equal("#{DRIVE}/?", File.expand_path("./?", "#{DRIVE}/"))
    assert_equal("#{Dir.pwd}/?", File.expand_path("./?", Dir.pwd))
  end if DRIVE

  def test_expand_path_does_not_modify_the_string_argument
    str = "./a/b/../c"
    assert_equal("#{Dir.pwd}/a/c", File.expand_path(str, Dir.pwd))
    assert_equal("./a/b/../c", str)
  end

  def test_expand_path_returns_a_string_when_passed_a_string_subclass
    sub = Class.new(String)
    str = sub.new "./a/b/../c"
    path = File.expand_path(str, Dir.pwd)
    assert_equal("#{Dir.pwd}/a/c", path)
    assert_instance_of(String, path)
  end

  def test_expand_path_accepts_objects_that_have_a_to_path_method
    klass = Class.new { def to_path; "a/b/c"; end }
    obj = klass.new
    assert_equal("#{Dir.pwd}/a/b/c", File.expand_path(obj))
  end

  def test_basename
    assert_equal(File.basename(@file).sub(/\.test$/, ""), File.basename(@file, ".test"))
    assert_equal("", s = File.basename(""))
    assert(!s.frozen?, '[ruby-core:24199]')
    assert_equal("foo", s = File.basename("foo"))
    assert(!s.frozen?, '[ruby-core:24199]')
    assert_equal("foo", File.basename("foo", ".ext"))
    assert_equal("foo", File.basename("foo.ext", ".ext"))
    assert_equal("foo", File.basename("foo.ext", ".*"))
    if /cygwin|mingw|mswin|bccwin/ =~ RUBY_PLATFORM
      basename = File.basename(@file)
      assert_equal(basename, File.basename(@file + " "))
      assert_equal(basename, File.basename(@file + "."))
      assert_equal(basename, File.basename(@file + "::$DATA"))
      basename.chomp!(".test")
      assert_equal(basename, File.basename(@file + " ", ".test"))
      assert_equal(basename, File.basename(@file + ".", ".test"))
      assert_equal(basename, File.basename(@file + "::$DATA", ".test"))
      assert_equal(basename, File.basename(@file + " ", ".*"))
      assert_equal(basename, File.basename(@file + ".", ".*"))
      assert_equal(basename, File.basename(@file + "::$DATA", ".*"))
    end
    if File::ALT_SEPARATOR == '\\'
      a = "foo/\225\\\\"
      [%W"cp437 \225", %W"cp932 \225\\"].each do |cp, expected|
        assert_equal(expected.force_encoding(cp), File.basename(a.dup.force_encoding(cp)), cp)
      end
    end

    assert_incompatible_encoding {|d| File.basename(d)}
    assert_incompatible_encoding {|d| File.basename(d, ".*")}
    assert_raise(Encoding::CompatibilityError) {File.basename("foo.ext", ".*".encode("utf-16le"))}

    s = "foo\x93_a".force_encoding("cp932")
    assert_equal(s, File.basename(s, "_a"))

    s = "\u4032.\u3024"
    assert_equal(s, File.basename(s, ".\x95\\".force_encoding("cp932")))
  end

  def test_dirname
    assert(@file.start_with?(File.dirname(@file)))
    assert_equal(".", File.dirname(""))
    assert_incompatible_encoding {|d| File.dirname(d)}
    if File::ALT_SEPARATOR == '\\'
      a = "\225\\\\foo"
      [%W"cp437 \225", %W"cp932 \225\\"].each do |cp, expected|
        assert_equal(expected.force_encoding(cp), File.dirname(a.dup.force_encoding(cp)), cp)
      end
    end
  end

  def test_extname
    assert_equal(".test", File.extname(@file))
    prefixes = ["", "/", ".", "/.", "bar/.", "/bar/."]
    infixes = ["", " ", "."]
    infixes2 = infixes + [".ext "]
    appendixes = [""]
    if /cygwin|mingw|mswin|bccwin/ =~ RUBY_PLATFORM
      appendixes << " " << "." << "::$DATA" << "::$DATA.bar"
    end
    prefixes.each do |prefix|
      appendixes.each do |appendix|
        infixes.each do |infix|
          path = "#{prefix}foo#{infix}#{appendix}"
          assert_equal("", File.extname(path), "File.extname(#{path.inspect})")
        end
        infixes2.each do |infix|
          path = "#{prefix}foo#{infix}.ext#{appendix}"
          assert_equal(".ext", File.extname(path), "File.extname(#{path.inspect})")
        end
      end
    end
    bug3175 = '[ruby-core:29627]'
    assert_equal(".rb", File.extname("/tmp//bla.rb"), bug3175)

    assert_incompatible_encoding {|d| File.extname(d)}
  end

  def test_split
    d, b = File.split(@file)
    assert_equal(File.dirname(@file), d)
    assert_equal(File.basename(@file), b)
  end

  def test_join
    s = "foo" + File::SEPARATOR + "bar" + File::SEPARATOR + "baz"
    assert_equal(s, File.join("foo", "bar", "baz"))
    assert_equal(s, File.join(["foo", "bar", "baz"]))

    o = Object.new
    def o.to_path; "foo"; end
    assert_equal(s, File.join(o, "bar", "baz"))
    assert_equal(s, File.join("foo" + File::SEPARATOR, "bar", File::SEPARATOR + "baz"))
  end

  def test_join_alt_separator
    if File::ALT_SEPARATOR == '\\'
      a = "\225\\"
      b = "foo"
      [%W"cp437 \225\\foo", %W"cp932 \225\\/foo"].each do |cp, expected|
        assert_equal(expected.force_encoding(cp), File.join(a.dup.force_encoding(cp), b.dup.force_encoding(cp)), cp)
      end
    end
  end

  def test_join_ascii_incompatible
    bug7168 = '[ruby-core:48012]'
    names = %w"a b".map {|s| s.encode(Encoding::UTF_16LE)}
    assert_raise(Encoding::CompatibilityError, bug7168) {File.join(*names)}
    assert_raise(Encoding::CompatibilityError, bug7168) {File.join(names)}

    a = Object.new
    b = names[1]
    names = [a, "b"]
    a.singleton_class.class_eval do
      define_method(:to_path) do
        names[1] = b
        "a"
      end
    end
    assert_raise(Encoding::CompatibilityError, bug7168) {File.join(names)}
  end

  def test_truncate
    assert_equal(0, File.truncate(@file, 1))
    assert_file.exist?(@file)
    assert_equal(1, File.size(@file))
    assert_equal(0, File.truncate(@file, 0))
    assert_file.exist?(@file)
    assert_file.zero?(@file)
    make_file("foo", @file)
    assert_raise(Errno::ENOENT) { File.truncate(@nofile, 0) }

    f = File.new(@file, "w")
    assert_equal(0, f.truncate(2))
    assert_file.exist?(@file)
    assert_equal(2, File.size(@file))
    assert_equal(0, f.truncate(0))
    assert_file.exist?(@file)
    assert_file.zero?(@file)
    f.close
    make_file("foo", @file)

    assert_raise(IOError) { File.open(@file) {|ff| ff.truncate(0)} }
  rescue NotImplementedError
  end

  def test_flock ## xxx
    f = File.new(@file, "r+")
    f.flock(File::LOCK_EX)
    f.flock(File::LOCK_SH)
    f.flock(File::LOCK_UN)
    f.close
  rescue NotImplementedError
  end

  def test_test
    sleep(@time - Time.now + 1.1)
    make_file("foo", @file + "2")
    [@dir, @file, @zerofile, @symlinkfile, @hardlinkfile].compact.each do |f|
      assert_equal(File.atime(f), test(?A, f))
      assert_equal(File.ctime(f), test(?C, f))
      assert_equal(File.mtime(f), test(?M, f))
      assert_equal(File.blockdev?(f), test(?b, f))
      assert_equal(File.chardev?(f), test(?c, f))
      assert_equal(File.directory?(f), test(?d, f))
      assert_equal(File.exist?(f), test(?e, f))
      assert_equal(File.file?(f), test(?f, f))
      assert_equal(File.setgid?(f), test(?g, f))
      assert_equal(File.grpowned?(f), test(?G, f))
      assert_equal(File.sticky?(f), test(?k, f))
      assert_equal(File.symlink?(f), test(?l, f))
      assert_equal(File.owned?(f), test(?o, f))
      assert_nothing_raised { test(?O, f) }
      assert_equal(File.pipe?(f), test(?p, f))
      assert_equal(File.readable?(f), test(?r, f))
      assert_equal(File.readable_real?(f), test(?R, f))
      assert_equal(File.size?(f), test(?s, f))
      assert_equal(File.socket?(f), test(?S, f))
      assert_equal(File.setuid?(f), test(?u, f))
      assert_equal(File.writable?(f), test(?w, f))
      assert_equal(File.writable_real?(f), test(?W, f))
      assert_equal(File.executable?(f), test(?x, f))
      assert_equal(File.executable_real?(f), test(?X, f))
      assert_equal(File.zero?(f), test(?z, f))
    end
    assert_equal(false, test(?-, @dir, @file))
    assert_equal(true, test(?-, @file, @file))
    assert_equal(true, test(?=, @file, @file))
    assert_equal(false, test(?>, @file, @file))
    assert_equal(false, test(?<, @file, @file))
    unless /cygwin/ =~ RUBY_PLATFORM
      assert_equal(false, test(?=, @file, @file + "2"))
      assert_equal(false, test(?>, @file, @file + "2"))
      assert_equal(true, test(?>, @file + "2", @file))
      assert_equal(true, test(?<, @file, @file + "2"))
      assert_equal(false, test(?<, @file + "2", @file))
    end
    assert_raise(ArgumentError) { test }
    assert_raise(Errno::ENOENT) { test(?A, @nofile) }
    assert_raise(ArgumentError) { test(?a) }
    assert_raise(ArgumentError) { test("\0".ord) }
  end

  def test_stat_init
    sleep(@time - Time.now + 1.1)
    make_file("foo", @file + "2")
    fs1, fs2 = File::Stat.new(@file), File::Stat.new(@file + "2")
    assert_nothing_raised do
      assert_equal(0, fs1 <=> fs1)
      assert_equal(-1, fs1 <=> fs2)
      assert_equal(1, fs2 <=> fs1)
      assert_nil(fs1 <=> nil)
      assert_integer(fs1.dev)
      assert_integer_or_nil(fs1.rdev)
      assert_integer_or_nil(fs1.dev_major)
      assert_integer_or_nil(fs1.dev_minor)
      assert_integer_or_nil(fs1.rdev_major)
      assert_integer_or_nil(fs1.rdev_minor)
      assert_integer(fs1.ino)
      assert_integer(fs1.mode)
      unless /emx|mswin|mingw/ =~ RUBY_PLATFORM
        # on Windows, nlink is always 1. but this behavior will be changed
        # in the future.
        assert_equal(@hardlinkfile ? 2 : 1, fs1.nlink)
      end
      assert_integer(fs1.uid)
      assert_integer(fs1.gid)
      assert_equal(3, fs1.size)
      assert_integer_or_nil(fs1.blksize)
      assert_integer_or_nil(fs1.blocks)
      assert_kind_of(Time, fs1.atime)
      assert_kind_of(Time, fs1.mtime)
      assert_kind_of(Time, fs1.ctime)
      assert_kind_of(String, fs1.inspect)
    end
    assert_raise(Errno::ENOENT) { File::Stat.new(@nofile) }
    assert_kind_of(File::Stat, File::Stat.new(@file).dup)
    assert_raise(TypeError) do
      File::Stat.new(@file).instance_eval { initialize_copy(0) }
    end
  end

  def test_stat_ftype
    assert_equal("directory", File::Stat.new(@dir).ftype)
    assert_equal("file", File::Stat.new(@file).ftype)
    # File::Stat uses stat
    assert_equal("file", File::Stat.new(@symlinkfile).ftype) if @symlinkfile
    assert_equal("file", File::Stat.new(@hardlinkfile).ftype) if @hardlinkfile
  end

  def test_stat_directory_p
    assert(File::Stat.new(@dir).directory?)
    assert(!(File::Stat.new(@file).directory?))
  end

  def test_stat_pipe_p ## xxx
    assert(!(File::Stat.new(@dir).pipe?))
    assert(!(File::Stat.new(@file).pipe?))
  end

  def test_stat_symlink_p
    assert(!(File::Stat.new(@dir).symlink?))
    assert(!(File::Stat.new(@file).symlink?))
    # File::Stat uses stat
    assert(!(File::Stat.new(@symlinkfile).symlink?)) if @symlinkfile
    assert(!(File::Stat.new(@hardlinkfile).symlink?)) if @hardlinkfile
  end

  def test_stat_socket_p ## xxx
    assert(!(File::Stat.new(@dir).socket?))
    assert(!(File::Stat.new(@file).socket?))
  end

  def test_stat_blockdev_p ## xxx
    assert(!(File::Stat.new(@dir).blockdev?))
    assert(!(File::Stat.new(@file).blockdev?))
  end

  def test_stat_chardev_p ## xxx
    assert(!(File::Stat.new(@dir).chardev?))
    assert(!(File::Stat.new(@file).chardev?))
  end

  def test_stat_readable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0200, @file)
    assert(!(File::Stat.new(@file).readable?))
    File.chmod(0600, @file)
    assert(File::Stat.new(@file).readable?)
  end

  def test_stat_readable_real_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0200, @file)
    assert(!(File::Stat.new(@file).readable_real?))
    File.chmod(0600, @file)
    assert(File::Stat.new(@file).readable_real?)
  end

  def test_stat_world_readable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0006, @file)
    assert(File::Stat.new(@file).world_readable?)
    File.chmod(0060, @file)
    assert(!(File::Stat.new(@file).world_readable?))
    File.chmod(0600, @file)
    assert(!(File::Stat.new(@file).world_readable?))
  end

  def test_stat_writable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0400, @file)
    assert(!(File::Stat.new(@file).writable?))
    File.chmod(0600, @file)
    assert(File::Stat.new(@file).writable?)
  end

  def test_stat_writable_real_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    return if Process.euid == 0
    File.chmod(0400, @file)
    assert(!(File::Stat.new(@file).writable_real?))
    File.chmod(0600, @file)
    assert(File::Stat.new(@file).writable_real?)
  end

  def test_stat_world_writable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0006, @file)
    assert(File::Stat.new(@file).world_writable?)
    File.chmod(0060, @file)
    assert(!(File::Stat.new(@file).world_writable?))
    File.chmod(0600, @file)
    assert(!(File::Stat.new(@file).world_writable?))
  end

  def test_stat_executable_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0100, @file)
    assert(File::Stat.new(@file).executable?)
    File.chmod(0600, @file)
    assert(!(File::Stat.new(@file).executable?))
  end

  def test_stat_executable_real_p
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    File.chmod(0100, @file)
    assert(File::Stat.new(@file).executable_real?)
    File.chmod(0600, @file)
    assert(!(File::Stat.new(@file).executable_real?))
  end

  def test_stat_file_p
    assert(!(File::Stat.new(@dir).file?))
    assert(File::Stat.new(@file).file?)
  end

  def test_stat_zero_p
    assert_nothing_raised { File::Stat.new(@dir).zero? }
    assert(!(File::Stat.new(@file).zero?))
    assert(File::Stat.new(@zerofile).zero?)
  end

  def test_stat_size_p
    assert_nothing_raised { File::Stat.new(@dir).size? }
    assert_equal(3, File::Stat.new(@file).size?)
    assert(!(File::Stat.new(@zerofile).size?))
  end

  def test_stat_owned_p ## xxx
    return if /cygwin|mswin|bccwin|mingw|emx/ =~ RUBY_PLATFORM
    assert(File::Stat.new(@file).owned?)
    assert(File::Stat.new(@file).grpowned?)
  end

  def test_stat_suid_sgid_sticky ## xxx
    assert(!(File::Stat.new(@file).setuid?))
    assert(!(File::Stat.new(@file).setgid?))
    assert(!(File::Stat.new(@file).sticky?))
  end

  def test_stat_size
    assert_integer(File::Stat.new(@dir).size)
    assert_equal(3, File::Stat.new(@file).size)
    assert_equal(0, File::Stat.new(@zerofile).size)
  end

  def test_stat_special_file
    # test for special files such as pagefile.sys on Windows
    assert_nothing_raised do
      Dir::glob("C:/*.sys") {|f| File::Stat.new(f) }
    end
  end if DRIVE

  def test_path_check
    assert_nothing_raised { ENV["PATH"] }
  end

  def test_find_file
    assert_raise(SecurityError) do
      Thread.new do
        $SAFE = 4
        load(@file)
      end.join
    end
  end

  def test_size
    assert_equal(3, File.open(@file) {|f| f.size })
    File.open(@file, "a") do |f|
      f.write("bar")
      assert_equal(6, f.size)
    end
  end

  def test_absolute_path
    assert_equal(File.join(Dir.pwd, "~foo"), File.absolute_path("~foo"))
    dir = File.expand_path("/bar")
    assert_equal(File.join(dir, "~foo"), File.absolute_path("~foo", dir))
  end
end
