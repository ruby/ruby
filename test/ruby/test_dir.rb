# frozen_string_literal: false
require 'test/unit'

require 'tmpdir'
require 'fileutils'

class TestDir < Test::Unit::TestCase

  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
    @root = File.realpath(Dir.mktmpdir('__test_dir__'))
    @nodir = File.join(@root, "dummy")
    for i in "a".."z"
      if i.ord % 2 == 0
        FileUtils.touch(File.join(@root, i))
      else
        FileUtils.mkdir(File.join(@root, i))
      end
    end
  end

  def teardown
    $VERBOSE = @verbose
    FileUtils.remove_entry_secure @root if File.directory?(@root)
  end

  def test_seek
    dir = Dir.open(@root)
    begin
      cache = []
      loop do
        pos = dir.tell
        break unless name = dir.read
        cache << [pos, name]
      end
      for x,y in cache.sort_by {|z| z[0] % 3 } # shuffle
        dir.seek(x)
        assert_equal(y, dir.read)
      end
    ensure
      dir.close
    end
  end

  def test_nodir
    assert_raise(Errno::ENOENT) { Dir.open(@nodir) }
  end

  def test_inspect
    d = Dir.open(@root)
    assert_match(/^#<Dir:#{ Regexp.quote(@root) }>$/, d.inspect)
    assert_match(/^#<Dir:.*>$/, Dir.allocate.inspect)
  ensure
    d.close
  end

  def test_path
    d = Dir.open(@root)
    assert_equal(@root, d.path)
    assert_nil(Dir.allocate.path)
  ensure
    d.close
  end

  def test_set_pos
    d = Dir.open(@root)
    loop do
      i = d.pos
      break unless x = d.read
      d.pos = i
      assert_equal(x, d.read)
    end
  ensure
    d.close
  end

  def test_rewind
    d = Dir.open(@root)
    a = (0..5).map { d.read }
    d.rewind
    b = (0..5).map { d.read }
    assert_equal(a, b)
  ensure
    d.close
  end

  def test_chdir
    @pwd = Dir.pwd
    @env_home = ENV["HOME"]
    @env_logdir = ENV["LOGDIR"]
    ENV.delete("HOME")
    ENV.delete("LOGDIR")

    assert_raise(Errno::ENOENT) { Dir.chdir(@nodir) }
    assert_raise(ArgumentError) { Dir.chdir }
    ENV["HOME"] = @pwd
    Dir.chdir do
      assert_equal(@pwd, Dir.pwd)
      Dir.chdir(@root)
      assert_equal(@root, Dir.pwd)
    end

  ensure
    begin
      Dir.chdir(@pwd)
    rescue
      abort("cannot return the original directory: #{ @pwd }")
    end
    if @env_home
      ENV["HOME"] = @env_home
    else
      ENV.delete("HOME")
    end
    if @env_logdir
      ENV["LOGDIR"] = @env_logdir
    else
      ENV.delete("LOGDIR")
    end
  end

  def test_chroot_nodir
    assert_raise(NotImplementedError, Errno::ENOENT, Errno::EPERM
		) { Dir.chroot(File.join(@nodir, "")) }
  end

  def test_close
    d = Dir.open(@root)
    d.close
    assert_nothing_raised(IOError) { d.close }
    assert_raise(IOError) { d.read }
  end

  def test_glob
    assert_equal((%w(. ..) + ("a".."z").to_a).map{|f| File.join(@root, f) },
                 Dir.glob(File.join(@root, "*"), File::FNM_DOTMATCH).sort)
    assert_equal([@root] + ("a".."z").map {|f| File.join(@root, f) }.sort,
                 Dir.glob([@root, File.join(@root, "*")]).sort)
    assert_equal([@root] + ("a".."z").map {|f| File.join(@root, f) }.sort,
                 Dir.glob(@root + "\0\0\0" + File.join(@root, "*")).sort)

    assert_equal(("a".."z").step(2).map {|f| File.join(File.join(@root, f), "") }.sort,
                 Dir.glob(File.join(@root, "*/")).sort)
    assert_equal([File.join(@root, '//a')], Dir.glob(@root + '//a'))

    FileUtils.touch(File.join(@root, "{}"))
    assert_equal(%w({} a).map{|f| File.join(@root, f) },
                 Dir.glob(File.join(@root, '{\{\},a}')))
    assert_equal([], Dir.glob(File.join(@root, '[')))
    assert_equal([], Dir.glob(File.join(@root, '[a-\\')))

    assert_equal([File.join(@root, "a")], Dir.glob(File.join(@root, 'a\\')))
    assert_equal(("a".."f").map {|f| File.join(@root, f) }.sort, Dir.glob(File.join(@root, '[abc/def]')).sort)

    open(File.join(@root, "}}{}"), "wb") {}
    open(File.join(@root, "}}a"), "wb") {}
    assert_equal(%w(}}{} }}a).map {|f| File.join(@root, f)}, Dir.glob(File.join(@root, '}}{\{\},a}')))
    assert_equal(%w(}}{} }}a b c).map {|f| File.join(@root, f)}, Dir.glob(File.join(@root, '{\}\}{\{\},a},b,c}')))
    assert_raise(ArgumentError) {
      Dir.glob([[@root, File.join(@root, "*")].join("\0")])
    }
  end

  def test_glob_recursive
    bug6977 = '[ruby-core:47418]'
    bug8006 = '[ruby-core:53108] [Bug #8006]'
    Dir.chdir(@root) do
      assert_include(Dir.glob("a/**/*", File::FNM_DOTMATCH), "a/.", bug8006)

      FileUtils.mkdir_p("a/b/c/d/e/f")
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/e/f"), bug6977)
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/d/e/f"), bug6977)
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/c/d/e/f"), bug6977)
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/b/c/d/e/f"), bug6977)
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/c/?/e/f"), bug6977)
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/c/**/d/e/f"), bug6977)
      assert_equal(["a/b/c/d/e/f"], Dir.glob("a/**/c/**/d/e/f"), bug6977)

      bug8283 = '[ruby-core:54387] [Bug #8283]'
      dirs = ["a/.x", "a/b/.y"]
      FileUtils.mkdir_p(dirs)
      dirs.map {|dir| open("#{dir}/z", "w") {}}
      assert_equal([], Dir.glob("a/**/z").sort, bug8283)
      assert_equal(["a/.x/z"], Dir.glob("a/**/.x/z"), bug8283)
      assert_equal(["a/.x/z"], Dir.glob("a/.x/**/z"), bug8283)
      assert_equal(["a/b/.y/z"], Dir.glob("a/**/.y/z"), bug8283)
    end
  end

  if Process.const_defined?(:RLIMIT_NOFILE)
    def test_glob_too_may_open_files
      assert_separately([], "#{<<-"begin;"}\n#{<<-'end;'}", chdir: @root)
      begin;
        n = 16
        Process.setrlimit(Process::RLIMIT_NOFILE, n)
        files = []
        begin
          n.times {files << File.open('b')}
        rescue Errno::EMFILE, Errno::ENFILE => e
        end
        assert_raise(e.class) {
          Dir.glob('*')
        }
      end;
    end
  end

  def assert_entries(entries)
    entries.sort!
    assert_equal(%w(. ..) + ("a".."z").to_a, entries)
  end

  def test_entries
    assert_entries(Dir.open(@root) {|dir| dir.entries})
    assert_raise(ArgumentError) {Dir.entries(@root+"\0")}
  end

  def test_foreach
    assert_entries(Dir.foreach(@root).to_a)
    assert_raise(ArgumentError) {Dir.foreach(@root+"\0").to_a}
  end

  def test_dir_enc
    dir = Dir.open(@root, encoding: "UTF-8")
    begin
      while name = dir.read
	assert_equal(Encoding.find("UTF-8"), name.encoding)
      end
    ensure
      dir.close
    end

    dir = Dir.open(@root, encoding: "ASCII-8BIT")
    begin
      while name = dir.read
	assert_equal(Encoding.find("ASCII-8BIT"), name.encoding)
      end
    ensure
      dir.close
    end
  end

  def test_unknown_keywords
    bug8060 = '[ruby-dev:47152] [Bug #8060]'
    assert_raise_with_message(ArgumentError, /unknown keyword/, bug8060) do
      Dir.open(@root, xawqij: "a") {}
    end
  end

  def test_symlink
    begin
      ["dummy", *"a".."z"].each do |f|
	File.symlink(File.join(@root, f),
		     File.join(@root, "symlink-#{ f }"))
      end
    rescue NotImplementedError, Errno::EACCES
      return
    end

    assert_equal([*"a".."z", *"symlink-a".."symlink-z"].each_slice(2).map {|f, _| File.join(@root, f + "/") }.sort,
		 Dir.glob(File.join(@root, "*/")).sort)

    assert_equal([@root + "/", *[*"a".."z"].each_slice(2).map {|f, _| File.join(@root, f + "/") }.sort],
                 Dir.glob(File.join(@root, "**/")).sort)
  end

  def test_glob_metachar
    bug8597 = '[ruby-core:55764] [Bug #8597]'
    assert_empty(Dir.glob(File.join(@root, "<")), bug8597)
  end

  def test_glob_cases
    feature5994 = "[ruby-core:42469] [Feature #5994]"
    feature5994 << "\nDir.glob should return the filename with actual cases on the filesystem"
    Dir.chdir(File.join(@root, "a")) do
      open("FileWithCases", "w") {}
      return unless File.exist?("filewithcases")
      assert_equal(%w"FileWithCases", Dir.glob("filewithcases"), feature5994)
    end
    Dir.chdir(@root) do
      assert_equal(%w"a/FileWithCases", Dir.glob("A/filewithcases"), feature5994)
    end
  end

  def test_glob_super_root
    bug9648 = '[ruby-core:61552] [Bug #9648]'
    roots = Dir.glob("/*")
    assert_equal(roots.map {|n| "/..#{n}"}, Dir.glob("/../*"), bug9648)
  end

  if /mswin|mingw/ =~ RUBY_PLATFORM
    def test_glob_legacy_short_name
      bug10819 = '[ruby-core:67954] [Bug #10819]'
      bug11206 = '[ruby-core:69435] [Bug #11206]'
      skip unless /\A\w:/ =~ ENV["ProgramFiles"]
      short = "#$&/PROGRA~1"
      skip unless File.directory?(short)
      entries = Dir.glob("#{short}/Common*")
      assert_not_empty(entries, bug10819)
      long = File.expand_path(short)
      assert_equal(Dir.glob("#{long}/Common*"), entries, bug10819)
      wild = short.sub(/1\z/, '*')
      assert_not_include(Dir.glob(wild), long, bug11206)
      assert_include(Dir.glob(wild, File::FNM_SHORTNAME), long, bug10819)
      assert_empty(entries - Dir.glob("#{wild}/Common*", File::FNM_SHORTNAME), bug10819)
    end
  end

  def test_home
    env_home = ENV["HOME"]
    env_logdir = ENV["LOGDIR"]
    ENV.delete("HOME")
    ENV.delete("LOGDIR")

    ENV["HOME"] = @nodir
    assert_nothing_raised(ArgumentError) {
      assert_equal(@nodir, Dir.home)
      assert_equal(@nodir, Dir.home(""))
      if user = ENV["USER"]
        ENV["HOME"] = env_home
        assert_equal(File.expand_path(env_home), Dir.home(user))
      end
    }
    %W[no:such:user \u{7559 5b88}:\u{756a}].each do |user|
      assert_raise_with_message(ArgumentError, /#{user}/) {Dir.home(user)}
    end
  ensure
    ENV["HOME"] = env_home
    ENV["LOGDIR"] = env_logdir
  end

  def test_symlinks_not_resolved
    Dir.mktmpdir do |dirname|
      Dir.chdir(dirname) do
        begin
          File.symlink('some-dir', 'dir-symlink')
        rescue NotImplementedError, Errno::EACCES
          return
        end

        Dir.mkdir('some-dir')
        File.write('some-dir/foo', 'some content')

        assert_equal [ 'dir-symlink', 'some-dir' ], Dir['*'].sort
        assert_equal [ 'dir-symlink', 'some-dir', 'some-dir/foo' ], Dir['**/*'].sort
      end
    end
  end

  def test_fileno
    Dir.open(".") {|d|
      if d.respond_to? :fileno
        assert_kind_of(Integer, d.fileno)
      else
        assert_raise(NotImplementedError) { d.fileno }
      end
    }
  end

  def test_empty?
    assert_not_send([Dir, :empty?, @root])
    a = File.join(@root, "a")
    assert_send([Dir, :empty?, a])
    %w[A .dot].each do |tmp|
      tmp = File.join(a, tmp)
      open(tmp, "w") {}
      assert_not_send([Dir, :empty?, a])
      File.delete(tmp)
      assert_send([Dir, :empty?, a])
      Dir.mkdir(tmp)
      assert_not_send([Dir, :empty?, a])
      Dir.rmdir(tmp)
      assert_send([Dir, :empty?, a])
    end
    assert_raise(Errno::ENOENT) {Dir.empty?(@nodir)}
    assert_not_send([Dir, :empty?, File.join(@root, "b")])
    assert_raise(ArgumentError) {Dir.empty?(@root+"\0")}
  end

  def test_glob_gc_for_fd
    assert_separately(["-C", @root], "#{<<-"begin;"}\n#{<<-"end;"}", timeout: 3)
    begin;
      Process.setrlimit(Process::RLIMIT_NOFILE, 50)
      begin
        tap {tap {tap {(0..100).map {open(IO::NULL)}}}}
      rescue Errno::EMFILE
      end
      list = Dir.glob("*").sort
      assert_not_empty(list)
      assert_equal([*"a".."z"], list)
    end;
  end if defined?(Process::RLIMIT_NOFILE)
end
