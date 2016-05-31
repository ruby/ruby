# frozen_string_literal: false
require "test/unit"
require "fileutils"
require "tmpdir"
require "socket"

class TestFileExhaustive < Test::Unit::TestCase
  DRIVE = Dir.pwd[%r'\A(?:[a-z]:|//[^/]+/[^/]+)'i]
  POSIX = /cygwin|mswin|bccwin|mingw|emx/ !~ RUBY_PLATFORM
  NTFS = !(/cygwin|mingw|mswin|bccwin/ !~ RUBY_PLATFORM)

  def assert_incompatible_encoding
    d = "\u{3042}\u{3044}".encode("utf-16le")
    assert_raise(Encoding::CompatibilityError) {yield d}
    m = Class.new {define_method(:to_path) {d}}
    assert_raise(Encoding::CompatibilityError) {yield m.new}
  end

  def setup
    @dir = Dir.mktmpdir("rubytest-file")
    File.chown(-1, Process.gid, @dir)
  end

  def teardown
    GC.start
    FileUtils.remove_entry_secure @dir
  end

  def make_tmp_filename(prefix)
    "#{@dir}/#{prefix}.test"
  end

  def rootdir
    return @rootdir if defined? @rootdir
    @rootdir = "#{DRIVE}/"
    @rootdir
  end

  def nofile
    return @nofile if defined? @nofile
    @nofile = make_tmp_filename("nofile")
    @nofile
  end

  def make_file(content, file)
    open(file, "w") {|fh| fh << content }
  end

  def zerofile
    return @zerofile if defined? @zerofile
    @zerofile = make_tmp_filename("zerofile")
    make_file("", @zerofile)
    @zerofile
  end

  def regular_file
    return @file if defined? @file
    @file = make_tmp_filename("file")
    make_file("foo", @file)
    @file
  end

  def utf8_file
    return @utf8file if defined? @utf8file
    @utf8file = make_tmp_filename("\u3066\u3059\u3068")
    make_file("foo", @utf8file)
    @utf8file
  end

  def notownedfile
    return @notownedfile if defined? @notownedfile
    if Process.euid != 0
      @notownedfile = '/'
    else
      @notownedfile = nil
    end
    @notownedfile
  end

  def suidfile
    return @suidfile if defined? @suidfile
    if POSIX
      @suidfile = make_tmp_filename("suidfile")
      make_file("", @suidfile)
      File.chmod 04500, @suidfile
      @suidfile
    else
      @suidfile = nil
    end
  end

  def sgidfile
    return @sgidfile if defined? @sgidfile
    if POSIX
      @sgidfile = make_tmp_filename("sgidfile")
      make_file("", @sgidfile)
      File.chmod 02500, @sgidfile
      @sgidfile
    else
      @sgidfile = nil
    end
  end

  def stickyfile
    return @stickyfile if defined? @stickyfile
    if POSIX
      @stickyfile = make_tmp_filename("stickyfile")
      Dir.mkdir(@stickyfile)
      File.chmod 01500, @stickyfile
      @stickyfile
    else
      @stickyfile = nil
    end
  end

  def symlinkfile
    return @symlinkfile if defined? @symlinkfile
    @symlinkfile = make_tmp_filename("symlinkfile")
    begin
      File.symlink(regular_file, @symlinkfile)
    rescue NotImplementedError, Errno::EACCES
      @symlinkfile = nil
    end
    @symlinkfile
  end

  def hardlinkfile
    return @hardlinkfile if defined? @hardlinkfile
    @hardlinkfile = make_tmp_filename("hardlinkfile")
    begin
      File.link(regular_file, @hardlinkfile)
    rescue NotImplementedError, Errno::EINVAL	# EINVAL for Windows Vista
      @hardlinkfile = nil
    end
    @hardlinkfile
  end

  def fifo
    return @fifo if defined? @fifo
    if POSIX
      fn = make_tmp_filename("fifo")
      File.mkfifo(fn)
      @fifo = fn
    else
      @fifo = nil
    end
    @fifo
  end

  def socket
    return @socket if defined? @socket
    if defined? UNIXServer
      socket = make_tmp_filename("s")
      UNIXServer.open(socket).close
      @socket = socket
    else
      @socket = nil
    end
  end

  def chardev
    return @chardev if defined? @chardev
    @chardev = File::NULL == "/dev/null" ? "/dev/null" : nil
    @chardev
  end

  def blockdev
    return @blockdev if defined? @blockdev
    if /linux/ =~ RUBY_PLATFORM
      @blockdev = %w[/dev/loop0 /dev/sda /dev/vda /dev/xvda1].find {|f| File.exist? f }
    else
      @blockdev = nil
    end
    @blockdev
  end

  def test_path
    [regular_file, utf8_file].each do |file|
      assert_equal(file, File.open(file) {|f| f.path})
      assert_equal(file, File.path(file))
      o = Object.new
      class << o; self; end.class_eval do
        define_method(:to_path) { file }
      end
      assert_equal(file, File.path(o))
    end
  end

  def assert_integer(n)
    assert_kind_of(Integer, n)
  end

  def assert_integer_or_nil(n)
    msg = ->{"#{n.inspect} is neither Integer nor nil."}
    if n
      assert_kind_of(Integer, n, msg)
    else
      assert_nil(n, msg)
    end
  end

  def test_stat
    fn1 = regular_file
    hardlinkfile
    sleep(1.1)
    fn2 = fn1 + "2"
    make_file("foo", fn2)
    fs1, fs2 = File.stat(fn1), File.stat(fn2)
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
        assert_equal(hardlinkfile ? 2 : 1, fs1.nlink)
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
    assert_raise(Errno::ENOENT) { File.stat(nofile) }
    assert_kind_of(File::Stat, File.open(fn1) {|f| f.stat})
    assert_raise(Errno::ENOENT) { File.lstat(nofile) }
    assert_kind_of(File::Stat, File.open(fn1) {|f| f.lstat})
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
  end if NTFS

  def test_lstat
    return unless symlinkfile
    assert_equal(false, File.stat(symlinkfile).symlink?)
    assert_equal(true, File.lstat(symlinkfile).symlink?)
    f = File.new(symlinkfile)
    assert_equal(false, f.stat.symlink?)
    assert_equal(true, f.lstat.symlink?)
    f.close
  end

  def test_directory_p
    assert_file.directory?(@dir)
    assert_file.not_directory?(@dir+"/...")
    assert_file.not_directory?(regular_file)
    assert_file.not_directory?(utf8_file)
    assert_file.not_directory?(nofile)
  end

  def test_pipe_p
    assert_file.not_pipe?(@dir)
    assert_file.not_pipe?(regular_file)
    assert_file.not_pipe?(utf8_file)
    assert_file.not_pipe?(nofile)
    assert_file.pipe?(fifo) if fifo
  end

  def test_symlink_p
    assert_file.not_symlink?(@dir)
    assert_file.not_symlink?(regular_file)
    assert_file.not_symlink?(utf8_file)
    assert_file.symlink?(symlinkfile) if symlinkfile
    assert_file.not_symlink?(hardlinkfile) if hardlinkfile
    assert_file.not_symlink?(nofile)
  end

  def test_socket_p
    assert_file.not_socket?(@dir)
    assert_file.not_socket?(regular_file)
    assert_file.not_socket?(utf8_file)
    assert_file.not_socket?(nofile)
    assert_file.socket?(socket) if socket
  end

  def test_blockdev_p
    assert_file.not_blockdev?(@dir)
    assert_file.not_blockdev?(regular_file)
    assert_file.not_blockdev?(utf8_file)
    assert_file.not_blockdev?(nofile)
    assert_file.blockdev?(blockdev) if blockdev
  end

  def test_chardev_p
    assert_file.not_chardev?(@dir)
    assert_file.not_chardev?(regular_file)
    assert_file.not_chardev?(utf8_file)
    assert_file.not_chardev?(nofile)
    assert_file.chardev?(chardev) if chardev
  end

  def test_exist_p
    assert_file.exist?(@dir)
    assert_file.exist?(regular_file)
    assert_file.exist?(utf8_file)
    assert_file.not_exist?(nofile)
  end

  def test_readable_p
    return if Process.euid == 0
    File.chmod(0200, regular_file)
    assert_file.not_readable?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.readable?(regular_file)

    File.chmod(0200, utf8_file)
    assert_file.not_readable?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.readable?(utf8_file)

    assert_file.not_readable?(nofile)
  end if POSIX

  def test_readable_real_p
    return if Process.euid == 0
    File.chmod(0200, regular_file)
    assert_file.not_readable_real?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.readable_real?(regular_file)

    File.chmod(0200, utf8_file)
    assert_file.not_readable_real?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.readable_real?(utf8_file)

    assert_file.not_readable_real?(nofile)
  end if POSIX

  def test_world_readable_p
    File.chmod(0006, regular_file)
    assert_file.world_readable?(regular_file)
    File.chmod(0060, regular_file)
    assert_file.not_world_readable?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.not_world_readable?(regular_file)

    File.chmod(0006, utf8_file)
    assert_file.world_readable?(utf8_file)
    File.chmod(0060, utf8_file)
    assert_file.not_world_readable?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.not_world_readable?(utf8_file)

    assert_file.not_world_readable?(nofile)
  end if POSIX

  def test_writable_p
    return if Process.euid == 0
    File.chmod(0400, regular_file)
    assert_file.not_writable?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.writable?(regular_file)

    File.chmod(0400, utf8_file)
    assert_file.not_writable?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.writable?(utf8_file)

    assert_file.not_writable?(nofile)
  end if POSIX

  def test_writable_real_p
    return if Process.euid == 0
    File.chmod(0400, regular_file)
    assert_file.not_writable_real?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.writable_real?(regular_file)

    File.chmod(0400, utf8_file)
    assert_file.not_writable_real?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.writable_real?(utf8_file)

    assert_file.not_writable_real?(nofile)
  end if POSIX

  def test_world_writable_p
    File.chmod(0006, regular_file)
    assert_file.world_writable?(regular_file)
    File.chmod(0060, regular_file)
    assert_file.not_world_writable?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.not_world_writable?(regular_file)

    File.chmod(0006, utf8_file)
    assert_file.world_writable?(utf8_file)
    File.chmod(0060, utf8_file)
    assert_file.not_world_writable?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.not_world_writable?(utf8_file)

    assert_file.not_world_writable?(nofile)
  end if POSIX

  def test_executable_p
    File.chmod(0100, regular_file)
    assert_file.executable?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.not_executable?(regular_file)

    File.chmod(0100, utf8_file)
    assert_file.executable?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.not_executable?(utf8_file)

    assert_file.not_executable?(nofile)
  end if POSIX

  def test_executable_real_p
    File.chmod(0100, regular_file)
    assert_file.executable_real?(regular_file)
    File.chmod(0600, regular_file)
    assert_file.not_executable_real?(regular_file)

    File.chmod(0100, utf8_file)
    assert_file.executable_real?(utf8_file)
    File.chmod(0600, utf8_file)
    assert_file.not_executable_real?(utf8_file)

    assert_file.not_executable_real?(nofile)
  end if POSIX

  def test_file_p
    assert_file.not_file?(@dir)
    assert_file.file?(regular_file)
    assert_file.file?(utf8_file)
    assert_file.not_file?(nofile)
  end

  def test_zero_p
    assert_nothing_raised { File.zero?(@dir) }
    assert_file.not_zero?(regular_file)
    assert_file.not_zero?(utf8_file)
    assert_file.zero?(zerofile)
    assert_file.not_zero?(nofile)
  end

  def test_empty_p
    assert_nothing_raised { File.empty?(@dir) }
    assert_file.not_empty?(regular_file)
    assert_file.not_empty?(utf8_file)
    assert_file.empty?(zerofile)
    assert_file.not_empty?(nofile)
  end

  def test_size_p
    assert_nothing_raised { File.size?(@dir) }
    assert_equal(3, File.size?(regular_file))
    assert_equal(3, File.size?(utf8_file))
    assert_file.not_size?(zerofile)
    assert_file.not_size?(nofile)
  end

  def test_owned_p
    assert_file.owned?(regular_file)
    assert_file.owned?(utf8_file)
    assert_file.not_owned?(notownedfile) if notownedfile
  end if POSIX

  def test_grpowned_p ## xxx
    assert_file.grpowned?(regular_file)
    assert_file.grpowned?(utf8_file)
  end if POSIX

  def test_suid
    assert_file.not_setuid?(regular_file)
    assert_file.not_setuid?(utf8_file)
    assert_file.setuid?(suidfile) if suidfile
  end

  def test_sgid
    assert_file.not_setgid?(regular_file)
    assert_file.not_setgid?(utf8_file)
    assert_file.setgid?(sgidfile) if sgidfile
  end

  def test_sticky
    assert_file.not_sticky?(regular_file)
    assert_file.not_sticky?(utf8_file)
    assert_file.sticky?(stickyfile) if stickyfile
  end

  def test_path_identical_p
    assert_file.identical?(regular_file, regular_file)
    assert_file.not_identical?(regular_file, zerofile)
    assert_file.not_identical?(regular_file, nofile)
    assert_file.not_identical?(nofile, regular_file)
  end

  def path_identical_p(file)
    [regular_file, utf8_file].each do |file|
      assert_file.identical?(file, file)
      assert_file.not_identical?(file, zerofile)
      assert_file.not_identical?(file, nofile)
      assert_file.not_identical?(nofile, file)
    end
  end

  def test_io_identical_p
    [regular_file, utf8_file].each do |file|
      open(file) {|f|
        assert_file.identical?(f, f)
        assert_file.identical?(file, f)
        assert_file.identical?(f, file)
      }
    end
  end

  def test_closed_io_identical_p
    [regular_file, utf8_file].each do |file|
      io = open(file) {|f| f}
      assert_raise(IOError) {
        File.identical?(file, io)
      }
      File.unlink(file)
      assert_file.not_exist?(file)
    end
  end

  def test_s_size
    assert_integer(File.size(@dir))
    assert_equal(3, File.size(regular_file))
    assert_equal(3, File.size(utf8_file))
    assert_equal(0, File.size(zerofile))
    assert_raise(Errno::ENOENT) { File.size(nofile) }
  end

  def test_ftype
    assert_equal("directory", File.ftype(@dir))
    assert_equal("file", File.ftype(regular_file))
    assert_equal("file", File.ftype(utf8_file))
    assert_equal("link", File.ftype(symlinkfile)) if symlinkfile
    assert_equal("file", File.ftype(hardlinkfile)) if hardlinkfile
    assert_raise(Errno::ENOENT) { File.ftype(nofile) }
  end

  def test_atime
    [regular_file, utf8_file].each do |file|
      t1 = File.atime(file)
      t2 = File.open(file) {|f| f.atime}
      assert_kind_of(Time, t1)
      assert_kind_of(Time, t2)
      assert_equal(t1, t2)
    end
    assert_raise(Errno::ENOENT) { File.atime(nofile) }
  end

  def test_mtime
    [regular_file, utf8_file].each do |file|
      t1 = File.mtime(file)
      t2 = File.open(file) {|f| f.mtime}
      assert_kind_of(Time, t1)
      assert_kind_of(Time, t2)
      assert_equal(t1, t2)
    end
    assert_raise(Errno::ENOENT) { File.mtime(nofile) }
  end

  def test_ctime
    [regular_file, utf8_file].each do |file|
      t1 = File.ctime(file)
      t2 = File.open(file) {|f| f.ctime}
      assert_kind_of(Time, t1)
      assert_kind_of(Time, t2)
      assert_equal(t1, t2)
    end
    assert_raise(Errno::ENOENT) { File.ctime(nofile) }
  end

  def test_chmod
    [regular_file, utf8_file].each do |file|
      assert_equal(1, File.chmod(0444, file))
      assert_equal(0444, File.stat(file).mode % 01000)
      assert_equal(0, File.open(file) {|f| f.chmod(0222)})
      assert_equal(0222, File.stat(file).mode % 01000)
      File.chmod(0600, file)
    end
    assert_raise(Errno::ENOENT) { File.chmod(0600, nofile) }
  end if POSIX

  def test_lchmod
    [regular_file, utf8_file].each do |file|
      assert_equal(1, File.lchmod(0444, file))
      assert_equal(0444, File.stat(file).mode % 01000)
      File.lchmod(0600, regular_file)
    end
    assert_raise(Errno::ENOENT) { File.lchmod(0600, nofile) }
  rescue NotImplementedError
  end if POSIX

  def test_chown ## xxx
  end

  def test_lchown ## xxx
  end

  def test_symlink
    return unless symlinkfile
    assert_equal("link", File.ftype(symlinkfile))
    assert_raise(Errno::EEXIST) { File.symlink(regular_file, regular_file) }
    assert_raise(Errno::EEXIST) { File.symlink(utf8_file, utf8_file) }
  end

  def test_utime
    t = Time.local(2000)
    File.utime(t + 1, t + 2, zerofile)
    assert_equal(t + 1, File.atime(zerofile))
    assert_equal(t + 2, File.mtime(zerofile))
  end

  def test_hardlink
    return unless hardlinkfile
    assert_equal("file", File.ftype(hardlinkfile))
    assert_raise(Errno::EEXIST) { File.link(regular_file, regular_file) }
    assert_raise(Errno::EEXIST) { File.link(utf8_file, utf8_file) }
  end

  def test_readlink
    return unless symlinkfile
    assert_equal(regular_file, File.readlink(symlinkfile))
    assert_raise(Errno::EINVAL) { File.readlink(regular_file) }
    assert_raise(Errno::EINVAL) { File.readlink(utf8_file) }
    assert_raise(Errno::ENOENT) { File.readlink(nofile) }
    if fs = Encoding.find("filesystem")
      assert_equal(fs, File.readlink(symlinkfile).encoding)
    end
  rescue NotImplementedError
  end

  def test_readlink_long_path
    return unless symlinkfile
    bug9157 = '[ruby-core:58592] [Bug #9157]'
    assert_separately(["-", symlinkfile, bug9157], "#{<<~begin}#{<<~"end;"}")
    begin
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

  if NTFS
    def test_readlink_junction
      base = File.basename(nofile)
      err = IO.popen(%W"cmd.exe /c mklink /j #{base} .", chdir: @dir, err: %i[child out], &:read)
      skip err unless $?.success?
      assert_equal(@dir, File.readlink(nofile))
    end

    def test_realpath_mount_point
      vol = IO.popen(["mountvol", DRIVE, "/l"], &:read).strip
      Dir.mkdir(mnt = File.join(@dir, mntpnt = "mntpnt"))
      system("mountvol", mntpnt, vol, chdir: @dir)
      assert_equal(mnt, File.realpath(mnt))
    ensure
      system("mountvol", mntpnt, "/d", chdir: @dir)
    end
  end

  def test_unlink
    assert_equal(1, File.unlink(regular_file))
    make_file("foo", regular_file)

    assert_equal(1, File.unlink(utf8_file))
    make_file("foo", utf8_file)

    assert_raise(Errno::ENOENT) { File.unlink(nofile) }
  end

  def test_rename
    [regular_file, utf8_file].each do |file|
      assert_equal(0, File.rename(file, nofile))
      assert_file.not_exist?(file)
      assert_file.exist?(nofile)
      assert_equal(0, File.rename(nofile, file))
      assert_raise(Errno::ENOENT) { File.rename(nofile, file) }
    end
  end

  def test_umask
    prev = File.umask(0777)
    assert_equal(0777, File.umask)
    open(nofile, "w") { }
    assert_equal(0, File.stat(nofile).mode % 01000)
    File.unlink(nofile)
    assert_equal(0777, File.umask(prev))
    assert_raise(ArgumentError) { File.umask(0, 1, 2) }
  end if POSIX

  def test_expand_path
    assert_equal(regular_file, File.expand_path(File.basename(regular_file), File.dirname(regular_file)))
    assert_equal(utf8_file, File.expand_path(File.basename(utf8_file), File.dirname(utf8_file)))
    if NTFS
      [regular_file, utf8_file].each do |file|
        assert_equal(file, File.expand_path(file + " "))
        assert_equal(file, File.expand_path(file + "."))
        assert_equal(file, File.expand_path(file + "::$DATA"))
      end
      assert_match(/\Ac:\//i, File.expand_path('c:'), '[ruby-core:31591]')
      assert_match(/\Ac:\//i, File.expand_path('c:foo', 'd:/bar'))
      assert_match(/\Ae:\//i, File.expand_path('e:foo', 'd:/bar'))
      assert_match(%r'\Ac:/bar/foo\z'i, File.expand_path('c:foo', 'c:/bar'))
    end
    case RUBY_PLATFORM
    when /darwin/
      ["\u{feff}", *"\u{2000}"..."\u{2100}"].each do |c|
        file = regular_file + c
        begin
          open(file) {}
        rescue
          assert_equal(file, File.expand_path(file), c.dump)
        else
          assert_equal(regular_file, File.expand_path(file), c.dump)
        end
      end
    end
    if DRIVE
      assert_match(%r"\Az:/foo\z"i, File.expand_path('/foo', "z:/bar"))
      assert_match(%r"\A//host/share/foo\z"i, File.expand_path('/foo', "//host/share/bar"))
      assert_match(%r"\A#{DRIVE}/foo\z"i, File.expand_path('/foo'))
    else
      assert_equal("/foo", File.expand_path('/foo'))
    end
  end

  def test_expand_path_memsize
    bug9934 = '[ruby-core:63114] [Bug #9934]'
    require "objspace"
    path = File.expand_path("/foo")
    assert_operator(ObjectSpace.memsize_of(path), :<=, path.bytesize + GC::INTERNAL_CONSTANTS[:RVALUE_SIZE], bug9934)
    path = File.expand_path("/a"*25)
    assert_equal(path.bytesize+1 + GC::INTERNAL_CONSTANTS[:RVALUE_SIZE], ObjectSpace.memsize_of(path), bug9934)
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
    assert_equal File.join(rootdir, "aaa"), File.expand_path("#{rootdir}/aaa::$DATA")
    assert_equal File.join(rootdir, "aa:a"), File.expand_path("#{rootdir}/aa:a:$DATA")
    assert_equal File.join(rootdir, "aaa:$DATA"), File.expand_path("#{rootdir}/aaa:$DATA")
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
    assert_equal(rootdir, File.expand_path(".", "#{rootdir}"))
  end

  def test_expand_path_ignores_supplied_dir_if_path_contains_a_drive_letter
    assert_equal(rootdir, File.expand_path(rootdir, "D:/"))
  end if DRIVE

  def test_expand_path_removes_trailing_slashes_from_absolute_path
    assert_equal(File.join(rootdir, "foo"), File.expand_path("#{rootdir}foo/"))
    assert_equal(File.join(rootdir, "foo.rb"), File.expand_path("#{rootdir}foo.rb/"))
  end

  def test_expand_path_removes_trailing_spaces_from_absolute_path
    assert_equal(File.join(rootdir, "a"), File.expand_path("#{rootdir}a "))
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

  def test_expand_path_for_existent_username
    user = ENV['USER']
    skip "ENV['USER'] is not set" unless user
    assert_equal(ENV['HOME'], File.expand_path("~#{user}"))
  end unless DRIVE

  def test_expand_path_error_for_nonexistent_username
    user = "\u{3086 3046 3066 3044}:\u{307F 3084 304A 3046}"
    assert_raise_with_message(ArgumentError, /#{user}/) {File.expand_path("~#{user}")}
  end unless DRIVE

  def test_expand_path_error_for_non_absolute_home
    old_home = ENV["HOME"]
    ENV["HOME"] = "./UserHome"
    assert_raise_with_message(ArgumentError, /non-absolute home/) {File.expand_path("~")}
  ensure
    ENV["HOME"] = old_home
  end

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

  def test_expand_path_with_drive_letter
    bug10858 = '[ruby-core:68130] [Bug #10858]'
    assert_match(%r'/bar/foo\z'i, File.expand_path('z:foo', 'bar'), bug10858)
    assert_equal('z:/bar/foo', File.expand_path('z:foo', '/bar'), bug10858)
  end if DRIVE

  def test_basename
    assert_equal(File.basename(regular_file).sub(/\.test$/, ""), File.basename(regular_file, ".test"))
    assert_equal(File.basename(utf8_file).sub(/\.test$/, ""), File.basename(utf8_file, ".test"))
    assert_equal("", s = File.basename(""))
    assert_not_predicate(s, :frozen?, '[ruby-core:24199]')
    assert_equal("foo", s = File.basename("foo"))
    assert_not_predicate(s, :frozen?, '[ruby-core:24199]')
    assert_equal("foo", File.basename("foo", ".ext"))
    assert_equal("foo", File.basename("foo.ext", ".ext"))
    assert_equal("foo", File.basename("foo.ext", ".*"))
    if NTFS
      [regular_file, utf8_file].each do |file|
        basename = File.basename(file)
        assert_equal(basename, File.basename(file + " "))
        assert_equal(basename, File.basename(file + "."))
        assert_equal(basename, File.basename(file + "::$DATA"))
        basename.chomp!(".test")
        assert_equal(basename, File.basename(file + " ", ".test"))
        assert_equal(basename, File.basename(file + ".", ".test"))
        assert_equal(basename, File.basename(file + "::$DATA", ".test"))
        assert_equal(basename, File.basename(file + " ", ".*"))
        assert_equal(basename, File.basename(file + ".", ".*"))
        assert_equal(basename, File.basename(file + "::$DATA", ".*"))
      end
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
    assert_equal(@dir, File.dirname(regular_file))
    assert_equal(@dir, File.dirname(utf8_file))
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
    assert_equal(".test", File.extname(regular_file))
    assert_equal(".test", File.extname(utf8_file))
    prefixes = ["", "/", ".", "/.", "bar/.", "/bar/."]
    infixes = ["", " ", "."]
    infixes2 = infixes + [".ext "]
    appendixes = [""]
    if NTFS
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
    [regular_file, utf8_file].each do |file|
      d, b = File.split(file)
      assert_equal(File.dirname(file), d)
      assert_equal(File.basename(file), b)
    end
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
    [regular_file, utf8_file].each do |file|
      assert_equal(0, File.truncate(file, 1))
      assert_file.exist?(file)
      assert_equal(1, File.size(file))
      assert_equal(0, File.truncate(file, 0))
      assert_file.exist?(file)
      assert_file.zero?(file)
      make_file("foo", file)
      assert_raise(Errno::ENOENT) { File.truncate(nofile, 0) }

      f = File.new(file, "w")
      assert_equal(0, f.truncate(2))
      assert_file.exist?(file)
      assert_equal(2, File.size(file))
      assert_equal(0, f.truncate(0))
      assert_file.exist?(file)
      assert_file.zero?(file)
      f.close
      make_file("foo", file)

      assert_raise(IOError) { File.open(file) {|ff| ff.truncate(0)} }
    end
  rescue NotImplementedError
  end

  def test_flock_exclusive
    File.open(regular_file, "r+") do |f|
      f.flock(File::LOCK_EX)
      assert_separately(["-rtimeout", "-", regular_file], "#{<<~begin}#{<<~"end;"}")
      begin
        open(ARGV[0], "r") do |f|
          Timeout.timeout(0.1) do
            assert(!f.flock(File::LOCK_SH|File::LOCK_NB))
          end
        end
      end;
      assert_separately(["-rtimeout", "-", regular_file], "#{<<~begin}#{<<~"end;"}")
      begin
        open(ARGV[0], "r") do |f|
          assert_raise(Timeout::Error) do
            Timeout.timeout(0.1) do
              f.flock(File::LOCK_SH)
            end
          end
        end
      end;
      f.flock(File::LOCK_UN)
    end
  rescue NotImplementedError
  end

  def test_flock_shared
    File.open(regular_file, "r+") do |f|
      f.flock(File::LOCK_SH)
      assert_separately(["-rtimeout", "-", regular_file], "#{<<~begin}#{<<~"end;"}")
      begin
        open(ARGV[0], "r") do |f|
          Timeout.timeout(0.1) do
            assert(f.flock(File::LOCK_SH))
          end
        end
      end;
      assert_separately(["-rtimeout", "-", regular_file], "#{<<~begin}#{<<~"end;"}")
      begin
        open(ARGV[0], "r+") do |f|
          assert_raise(Timeout::Error) do
            Timeout.timeout(0.1) do
              f.flock(File::LOCK_EX)
            end
          end
        end
      end;
      f.flock(File::LOCK_UN)
    end
  rescue NotImplementedError
  end

  def test_test
    fn1 = regular_file
    hardlinkfile
    sleep(1.1)
    fn2 = fn1 + "2"
    make_file("foo", fn2)
    [
      @dir,
      fn1,
      zerofile,
      notownedfile,
      suidfile,
      sgidfile,
      stickyfile,
      symlinkfile,
      hardlinkfile,
      chardev,
      blockdev,
      fifo,
      socket
    ].compact.each do |f|
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
    assert_equal(false, test(?-, @dir, fn1))
    assert_equal(true, test(?-, fn1, fn1))
    assert_equal(true, test(?=, fn1, fn1))
    assert_equal(false, test(?>, fn1, fn1))
    assert_equal(false, test(?<, fn1, fn1))
    unless /cygwin/ =~ RUBY_PLATFORM
      assert_equal(false, test(?=, fn1, fn2))
      assert_equal(false, test(?>, fn1, fn2))
      assert_equal(true, test(?>, fn2, fn1))
      assert_equal(true, test(?<, fn1, fn2))
      assert_equal(false, test(?<, fn2, fn1))
    end
    assert_raise(ArgumentError) { test }
    assert_raise(Errno::ENOENT) { test(?A, nofile) }
    assert_raise(ArgumentError) { test(?a) }
    assert_raise(ArgumentError) { test("\0".ord) }
  end

  def test_stat_init
    fn1 = regular_file
    hardlinkfile
    sleep(1.1)
    fn2 = fn1 + "2"
    make_file("foo", fn2)
    fs1, fs2 = File::Stat.new(fn1), File::Stat.new(fn2)
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
        assert_equal(hardlinkfile ? 2 : 1, fs1.nlink)
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
    assert_raise(Errno::ENOENT) { File::Stat.new(nofile) }
    assert_kind_of(File::Stat, File::Stat.new(fn1).dup)
    assert_raise(TypeError) do
      File::Stat.new(fn1).instance_eval { initialize_copy(0) }
    end
  end

  def test_stat_new_utf8
    assert_nothing_raised do
      File::Stat.new(utf8_file)
    end
  end

  def test_stat_ftype
    assert_equal("directory", File::Stat.new(@dir).ftype)
    assert_equal("file", File::Stat.new(regular_file).ftype)
    # File::Stat uses stat
    assert_equal("file", File::Stat.new(symlinkfile).ftype) if symlinkfile
    assert_equal("file", File::Stat.new(hardlinkfile).ftype) if hardlinkfile
  end

  def test_stat_directory_p
    assert_predicate(File::Stat.new(@dir), :directory?)
    assert_not_predicate(File::Stat.new(regular_file), :directory?)
  end

  def test_stat_pipe_p
    assert_not_predicate(File::Stat.new(@dir), :pipe?)
    assert_not_predicate(File::Stat.new(regular_file), :pipe?)
    assert_predicate(File::Stat.new(fifo), :pipe?) if fifo
    IO.pipe {|r, w|
      assert_predicate(r.stat, :pipe?)
      assert_predicate(w.stat, :pipe?)
    }
  end

  def test_stat_symlink_p
    assert_not_predicate(File::Stat.new(@dir), :symlink?)
    assert_not_predicate(File::Stat.new(regular_file), :symlink?)
    # File::Stat uses stat
    assert_not_predicate(File::Stat.new(symlinkfile), :symlink?) if symlinkfile
    assert_not_predicate(File::Stat.new(hardlinkfile), :symlink?) if hardlinkfile
  end

  def test_stat_socket_p
    assert_not_predicate(File::Stat.new(@dir), :socket?)
    assert_not_predicate(File::Stat.new(regular_file), :socket?)
    assert_predicate(File::Stat.new(socket), :socket?) if socket
  end

  def test_stat_blockdev_p
    assert_not_predicate(File::Stat.new(@dir), :blockdev?)
    assert_not_predicate(File::Stat.new(regular_file), :blockdev?)
    assert_predicate(File::Stat.new(blockdev), :blockdev?) if blockdev
  end

  def test_stat_chardev_p
    assert_not_predicate(File::Stat.new(@dir), :chardev?)
    assert_not_predicate(File::Stat.new(regular_file), :chardev?)
    assert_predicate(File::Stat.new(chardev), :chardev?) if chardev
  end

  def test_stat_readable_p
    return if Process.euid == 0
    File.chmod(0200, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :readable?)
    File.chmod(0600, regular_file)
    assert_predicate(File::Stat.new(regular_file), :readable?)
  end if POSIX

  def test_stat_readable_real_p
    return if Process.euid == 0
    File.chmod(0200, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :readable_real?)
    File.chmod(0600, regular_file)
    assert_predicate(File::Stat.new(regular_file), :readable_real?)
  end if POSIX

  def test_stat_world_readable_p
    File.chmod(0006, regular_file)
    assert_predicate(File::Stat.new(regular_file), :world_readable?)
    File.chmod(0060, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :world_readable?)
    File.chmod(0600, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :world_readable?)
  end if POSIX

  def test_stat_writable_p
    return if Process.euid == 0
    File.chmod(0400, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :writable?)
    File.chmod(0600, regular_file)
    assert_predicate(File::Stat.new(regular_file), :writable?)
  end if POSIX

  def test_stat_writable_real_p
    return if Process.euid == 0
    File.chmod(0400, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :writable_real?)
    File.chmod(0600, regular_file)
    assert_predicate(File::Stat.new(regular_file), :writable_real?)
  end if POSIX

  def test_stat_world_writable_p
    File.chmod(0006, regular_file)
    assert_predicate(File::Stat.new(regular_file), :world_writable?)
    File.chmod(0060, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :world_writable?)
    File.chmod(0600, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :world_writable?)
  end if POSIX

  def test_stat_executable_p
    File.chmod(0100, regular_file)
    assert_predicate(File::Stat.new(regular_file), :executable?)
    File.chmod(0600, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :executable?)
  end if POSIX

  def test_stat_executable_real_p
    File.chmod(0100, regular_file)
    assert_predicate(File::Stat.new(regular_file), :executable_real?)
    File.chmod(0600, regular_file)
    assert_not_predicate(File::Stat.new(regular_file), :executable_real?)
  end if POSIX

  def test_stat_file_p
    assert_not_predicate(File::Stat.new(@dir), :file?)
    assert_predicate(File::Stat.new(regular_file), :file?)
  end

  def test_stat_zero_p
    assert_nothing_raised { File::Stat.new(@dir).zero? }
    assert_not_predicate(File::Stat.new(regular_file), :zero?)
    assert_predicate(File::Stat.new(zerofile), :zero?)
  end

  def test_stat_size_p
    assert_nothing_raised { File::Stat.new(@dir).size? }
    assert_equal(3, File::Stat.new(regular_file).size?)
    assert_not_predicate(File::Stat.new(zerofile), :size?)
  end

  def test_stat_owned_p
    assert_predicate(File::Stat.new(regular_file), :owned?)
    assert_not_predicate(File::Stat.new(notownedfile), :owned?) if notownedfile
  end if POSIX

  def test_stat_grpowned_p ## xxx
    assert_predicate(File::Stat.new(regular_file), :grpowned?)
  end if POSIX

  def test_stat_suid
    assert_not_predicate(File::Stat.new(regular_file), :setuid?)
    assert_predicate(File::Stat.new(suidfile), :setuid?) if suidfile
  end

  def test_stat_sgid
    assert_not_predicate(File::Stat.new(regular_file), :setgid?)
    assert_predicate(File::Stat.new(sgidfile), :setgid?) if sgidfile
  end

  def test_stat_sticky
    assert_not_predicate(File::Stat.new(regular_file), :sticky?)
    assert_predicate(File::Stat.new(stickyfile), :sticky?) if stickyfile
  end

  def test_stat_size
    assert_integer(File::Stat.new(@dir).size)
    assert_equal(3, File::Stat.new(regular_file).size)
    assert_equal(0, File::Stat.new(zerofile).size)
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

  def test_size
    [regular_file, utf8_file].each do |file|
      assert_equal(3, File.open(file) {|f| f.size })
      File.open(file, "a") do |f|
        f.write("bar")
        assert_equal(6, f.size)
      end
    end
  end

  def test_absolute_path
    assert_equal(File.join(Dir.pwd, "~foo"), File.absolute_path("~foo"))
    dir = File.expand_path("/bar")
    assert_equal(File.join(dir, "~foo"), File.absolute_path("~foo", dir))
  end
end
