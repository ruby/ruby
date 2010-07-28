#!/usr/bin/env ruby

require 'test/unit'
require 'pathname'

require 'fileutils'
require 'tmpdir'
require 'enumerator'

class TestPathname < Test::Unit::TestCase
  def self.define_assertion(name, &block)
    @defassert_num ||= {}
    @defassert_num[name] ||= 0
    @defassert_num[name] += 1
    define_method("test_#{name}_#{@defassert_num[name]}", &block)
  end

  def self.defassert(name, result, *args)
    define_assertion(name) {
      assert_equal(result, self.send(name, *args), "#{name}(#{args.map {|a| a.inspect }.join(', ')})")
    }
  end

  DOSISH = File::ALT_SEPARATOR != nil
  DOSISH_DRIVE_LETTER = File.dirname("A:") == "A:."
  DOSISH_UNC = File.dirname("//") == "//"

  def cleanpath_aggressive(path)
    Pathname.new(path).cleanpath.to_s
  end

  defassert(:cleanpath_aggressive, '/',       '/')
  defassert(:cleanpath_aggressive, '.',       '')
  defassert(:cleanpath_aggressive, '.',       '.')
  defassert(:cleanpath_aggressive, '..',      '..')
  defassert(:cleanpath_aggressive, 'a',       'a')
  defassert(:cleanpath_aggressive, '/',       '/.')
  defassert(:cleanpath_aggressive, '/',       '/..')
  defassert(:cleanpath_aggressive, '/a',      '/a')
  defassert(:cleanpath_aggressive, '.',       './')
  defassert(:cleanpath_aggressive, '..',      '../')
  defassert(:cleanpath_aggressive, 'a',       'a/')
  defassert(:cleanpath_aggressive, 'a/b',     'a//b')
  defassert(:cleanpath_aggressive, 'a',       'a/.')
  defassert(:cleanpath_aggressive, 'a',       'a/./')
  defassert(:cleanpath_aggressive, '.',       'a/..')
  defassert(:cleanpath_aggressive, '.',       'a/../')
  defassert(:cleanpath_aggressive, '/a',      '/a/.')
  defassert(:cleanpath_aggressive, '..',      './..')
  defassert(:cleanpath_aggressive, '..',      '../.')
  defassert(:cleanpath_aggressive, '..',      './../')
  defassert(:cleanpath_aggressive, '..',      '.././')
  defassert(:cleanpath_aggressive, '/',       '/./..')
  defassert(:cleanpath_aggressive, '/',       '/../.')
  defassert(:cleanpath_aggressive, '/',       '/./../')
  defassert(:cleanpath_aggressive, '/',       '/.././')
  defassert(:cleanpath_aggressive, 'a/b/c',   'a/b/c')
  defassert(:cleanpath_aggressive, 'b/c',     './b/c')
  defassert(:cleanpath_aggressive, 'a/c',     'a/./c')
  defassert(:cleanpath_aggressive, 'a/b',     'a/b/.')
  defassert(:cleanpath_aggressive, '.',       'a/../.')
  defassert(:cleanpath_aggressive, '/a',      '/../.././../a')
  defassert(:cleanpath_aggressive, '../../d', 'a/b/../../../../c/../d')

  if DOSISH_UNC
    defassert(:cleanpath_aggressive, '//a/b/c', '//a/b/c/')
  else
    defassert(:cleanpath_aggressive, '/',       '///')
    defassert(:cleanpath_aggressive, '/a',      '///a')
    defassert(:cleanpath_aggressive, '/',       '///..')
    defassert(:cleanpath_aggressive, '/',       '///.')
    defassert(:cleanpath_aggressive, '/',       '///a/../..')
  end

  def cleanpath_conservative(path)
    Pathname.new(path).cleanpath(true).to_s
  end

  defassert(:cleanpath_conservative, '/',      '/')
  defassert(:cleanpath_conservative, '.',      '')
  defassert(:cleanpath_conservative, '.',      '.')
  defassert(:cleanpath_conservative, '..',     '..')
  defassert(:cleanpath_conservative, 'a',      'a')
  defassert(:cleanpath_conservative, '/',      '/.')
  defassert(:cleanpath_conservative, '/',      '/..')
  defassert(:cleanpath_conservative, '/a',     '/a')
  defassert(:cleanpath_conservative, '.',      './')
  defassert(:cleanpath_conservative, '..',     '../')
  defassert(:cleanpath_conservative, 'a/',     'a/')
  defassert(:cleanpath_conservative, 'a/b',    'a//b')
  defassert(:cleanpath_conservative, 'a/.',    'a/.')
  defassert(:cleanpath_conservative, 'a/.',    'a/./')
  defassert(:cleanpath_conservative, 'a/..',   'a/../')
  defassert(:cleanpath_conservative, '/a/.',   '/a/.')
  defassert(:cleanpath_conservative, '..',     './..')
  defassert(:cleanpath_conservative, '..',     '../.')
  defassert(:cleanpath_conservative, '..',     './../')
  defassert(:cleanpath_conservative, '..',     '.././')
  defassert(:cleanpath_conservative, '/',      '/./..')
  defassert(:cleanpath_conservative, '/',      '/../.')
  defassert(:cleanpath_conservative, '/',      '/./../')
  defassert(:cleanpath_conservative, '/',      '/.././')
  defassert(:cleanpath_conservative, 'a/b/c',  'a/b/c')
  defassert(:cleanpath_conservative, 'b/c',    './b/c')
  defassert(:cleanpath_conservative, 'a/c',    'a/./c')
  defassert(:cleanpath_conservative, 'a/b/.',  'a/b/.')
  defassert(:cleanpath_conservative, 'a/..',   'a/../.')
  defassert(:cleanpath_conservative, '/a',     '/../.././../a')
  defassert(:cleanpath_conservative, 'a/b/../../../../c/../d', 'a/b/../../../../c/../d')

  if DOSISH_UNC
    defassert(:cleanpath_conservative, '//',     '//')
  else
    defassert(:cleanpath_conservative, '/',      '//')
  end

  # has_trailing_separator?(path) -> bool
  def has_trailing_separator?(path)
    Pathname.allocate.__send__(:has_trailing_separator?, path)
  end

  defassert(:has_trailing_separator?, false, "/")
  defassert(:has_trailing_separator?, false, "///")
  defassert(:has_trailing_separator?, false, "a")
  defassert(:has_trailing_separator?, true, "a/")

  def add_trailing_separator(path)
    Pathname.allocate.__send__(:add_trailing_separator, path)
  end

  def del_trailing_separator(path)
    Pathname.allocate.__send__(:del_trailing_separator, path)
  end

  defassert(:del_trailing_separator, "/", "/")
  defassert(:del_trailing_separator, "/a", "/a")
  defassert(:del_trailing_separator, "/a", "/a/")
  defassert(:del_trailing_separator, "/a", "/a//")
  defassert(:del_trailing_separator, ".", ".")
  defassert(:del_trailing_separator, ".", "./")
  defassert(:del_trailing_separator, ".", ".//")

  if DOSISH_DRIVE_LETTER
    defassert(:del_trailing_separator, "A:", "A:")
    defassert(:del_trailing_separator, "A:/", "A:/")
    defassert(:del_trailing_separator, "A:/", "A://")
    defassert(:del_trailing_separator, "A:.", "A:.")
    defassert(:del_trailing_separator, "A:.", "A:./")
    defassert(:del_trailing_separator, "A:.", "A:.//")
  end

  if DOSISH_UNC
    defassert(:del_trailing_separator, "//", "//")
    defassert(:del_trailing_separator, "//a", "//a")
    defassert(:del_trailing_separator, "//a", "//a/")
    defassert(:del_trailing_separator, "//a", "//a//")
    defassert(:del_trailing_separator, "//a/b", "//a/b")
    defassert(:del_trailing_separator, "//a/b", "//a/b/")
    defassert(:del_trailing_separator, "//a/b", "//a/b//")
    defassert(:del_trailing_separator, "//a/b/c", "//a/b/c")
    defassert(:del_trailing_separator, "//a/b/c", "//a/b/c/")
    defassert(:del_trailing_separator, "//a/b/c", "//a/b/c//")
  else
    defassert(:del_trailing_separator, "/", "///")
    defassert(:del_trailing_separator, "///a", "///a/")
  end

  if DOSISH
    defassert(:del_trailing_separator, "a", "a\\")
    require 'Win32API'
    if Win32API.new('kernel32', 'GetACP', nil, 'L').call == 932
      defassert(:del_trailing_separator, "\225\\", "\225\\\\") # SJIS
    end
  end

  def plus(path1, path2) # -> path
    (Pathname.new(path1) + Pathname.new(path2)).to_s
  end

  defassert(:plus, '/', '/', '/')
  defassert(:plus, 'a/b', 'a', 'b')
  defassert(:plus, 'a', 'a', '.')
  defassert(:plus, 'b', '.', 'b')
  defassert(:plus, '.', '.', '.')
  defassert(:plus, '/b', 'a', '/b')

  defassert(:plus, '/', '/', '..')
  defassert(:plus, '.', 'a', '..')
  defassert(:plus, 'a', 'a/b', '..')
  defassert(:plus, '../..', '..', '..')
  defassert(:plus, '/c', '/', '../c')
  defassert(:plus, 'c', 'a', '../c')
  defassert(:plus, 'a/c', 'a/b', '../c')
  defassert(:plus, '../../c', '..', '../c')

  defassert(:plus, 'a//b/d//e', 'a//b/c', '../d//e')

  def relative?(path)
    Pathname.new(path).relative?
  end

  defassert(:relative?, false, '/')
  defassert(:relative?, false, '/a')
  defassert(:relative?, false, '/..')
  defassert(:relative?, true, 'a')
  defassert(:relative?, true, 'a/b')

  if DOSISH_DRIVE_LETTER
    defassert(:relative?, false, 'A:')
    defassert(:relative?, false, 'A:/')
    defassert(:relative?, false, 'A:/a')
  end

  if File.dirname('//') == '//'
    defassert(:relative?, false, '//')
    defassert(:relative?, false, '//a')
    defassert(:relative?, false, '//a/')
    defassert(:relative?, false, '//a/b')
    defassert(:relative?, false, '//a/b/')
    defassert(:relative?, false, '//a/b/c')
  end

  def relative_path_from(dest_directory, base_directory)
    Pathname.new(dest_directory).relative_path_from(Pathname.new(base_directory)).to_s
  end

  defassert(:relative_path_from, "../a", "a", "b")
  defassert(:relative_path_from, "../a", "a", "b/")
  defassert(:relative_path_from, "../a", "a/", "b")
  defassert(:relative_path_from, "../a", "a/", "b/")
  defassert(:relative_path_from, "../a", "/a", "/b")
  defassert(:relative_path_from, "../a", "/a", "/b/")
  defassert(:relative_path_from, "../a", "/a/", "/b")
  defassert(:relative_path_from, "../a", "/a/", "/b/")

  defassert(:relative_path_from, "../b", "a/b", "a/c")
  defassert(:relative_path_from, "../a", "../a", "../b")

  defassert(:relative_path_from, "a", "a", ".")
  defassert(:relative_path_from, "..", ".", "a")

  defassert(:relative_path_from, ".", ".", ".")
  defassert(:relative_path_from, ".", "..", "..")
  defassert(:relative_path_from, "..", "..", ".")

  defassert(:relative_path_from, "c/d", "/a/b/c/d", "/a/b")
  defassert(:relative_path_from, "../..", "/a/b", "/a/b/c/d")
  defassert(:relative_path_from, "../../../../e", "/e", "/a/b/c/d")
  defassert(:relative_path_from, "../b/c", "a/b/c", "a/d")

  defassert(:relative_path_from, "../a", "/../a", "/b")
  defassert(:relative_path_from, "../../a", "../a", "b")
  defassert(:relative_path_from, ".", "/a/../../b", "/b")
  defassert(:relative_path_from, "..", "a/..", "a")
  defassert(:relative_path_from, ".", "a/../b", "b")

  defassert(:relative_path_from, "a", "a", "b/..")
  defassert(:relative_path_from, "b/c", "b/c", "b/..")

  def self.defassert_raise(name, exc, *args)
    define_assertion(name) {
      message = "#{name}(#{args.map {|a| a.inspect }.join(', ')})"
      assert_raise(exc, message) { self.send(name, *args) }
    }
  end

  defassert_raise(:relative_path_from, ArgumentError, "/", ".")
  defassert_raise(:relative_path_from, ArgumentError, ".", "/")
  defassert_raise(:relative_path_from, ArgumentError, "a", "..")
  defassert_raise(:relative_path_from, ArgumentError, ".", "..")

  def with_tmpchdir(base=nil)
    Dir.mktmpdir(base) {|d|
      d = Pathname.new(d).realpath.to_s
      Dir.chdir(d) {
        yield d
      }
    }
  end

  def has_symlink?
    begin
      File.symlink(nil, nil)
    rescue NotImplementedError
      return false
    rescue TypeError
    end
    return true
  end

  def realpath(path, basedir=nil)
    Pathname.new(path).realpath(basedir).to_s
  end

  def test_realpath
    return if !has_symlink?
    with_tmpchdir('rubytest-pathname') {|dir|
      assert_raise(Errno::ENOENT) { realpath("#{dir}/not-exist") }
      File.symlink("not-exist-target", "#{dir}/not-exist")
      assert_raise(Errno::ENOENT) { realpath("#{dir}/not-exist") }

      File.symlink("loop", "#{dir}/loop")
      assert_raise(Errno::ELOOP) { realpath("#{dir}/loop") }
      assert_raise(Errno::ELOOP) { realpath("#{dir}/loop", dir) }

      File.symlink("../#{File.basename(dir)}/./not-exist-target", "#{dir}/not-exist2")
      assert_raise(Errno::ENOENT) { realpath("#{dir}/not-exist2") }

      File.open("#{dir}/exist-target", "w") {}
      File.symlink("../#{File.basename(dir)}/./exist-target", "#{dir}/exist2")
      assert_nothing_raised { realpath("#{dir}/exist2") }

      File.symlink("loop-relative", "loop-relative")
      assert_raise(Errno::ELOOP) { realpath("#{dir}/loop-relative") }

      Dir.mkdir("exist")
      assert_equal("#{dir}/exist", realpath("exist"))
      assert_raise(Errno::ELOOP) { realpath("../loop", "#{dir}/exist") }

      File.symlink("loop1/loop1", "loop1")
      assert_raise(Errno::ELOOP) { realpath("#{dir}/loop1") }

      File.symlink("loop2", "loop3")
      File.symlink("loop3", "loop2")
      assert_raise(Errno::ELOOP) { realpath("#{dir}/loop2") }

      Dir.mkdir("b")

      File.symlink("b", "c")
      assert_equal("#{dir}/b", realpath("c"))
      assert_equal("#{dir}/b", realpath("c/../c"))
      assert_equal("#{dir}/b", realpath("c/../c/../c/."))

      File.symlink("..", "b/d")
      assert_equal("#{dir}/b", realpath("c/d/c/d/c"))

      File.symlink("#{dir}/b", "e")
      assert_equal("#{dir}/b", realpath("e"))

      Dir.mkdir("f")
      Dir.mkdir("f/g")
      File.symlink("f/g", "h")
      assert_equal("#{dir}/f/g", realpath("h"))
      File.chmod(0000, "f")
      assert_raise(Errno::EACCES) { realpath("h") }
      File.chmod(0755, "f")
    }
  end

  def realdirpath(path)
    Pathname.new(path).realdirpath.to_s
  end

  def test_realdirpath
    return if !has_symlink?
    Dir.mktmpdir('rubytest-pathname') {|dir|
      rdir = realpath(dir)
      assert_equal("#{rdir}/not-exist", realdirpath("#{dir}/not-exist"))
      assert_raise(Errno::ENOENT) { realdirpath("#{dir}/not-exist/not-exist-child") }
      File.symlink("not-exist-target", "#{dir}/not-exist")
      assert_equal("#{rdir}/not-exist-target", realdirpath("#{dir}/not-exist"))
      File.symlink("../#{File.basename(dir)}/./not-exist-target", "#{dir}/not-exist2")
      assert_equal("#{rdir}/not-exist-target", realdirpath("#{dir}/not-exist2"))
      File.open("#{dir}/exist-target", "w") {}
      File.symlink("../#{File.basename(dir)}/./exist-target", "#{dir}/exist")
      assert_equal("#{rdir}/exist-target", realdirpath("#{dir}/exist"))
      File.symlink("loop", "#{dir}/loop")
      assert_raise(Errno::ELOOP) { realdirpath("#{dir}/loop") }
    }
  end

  def descend(path)
    Pathname.new(path).enum_for(:descend).map {|v| v.to_s }
  end

  defassert(:descend, %w[/ /a /a/b /a/b/c], "/a/b/c")
  defassert(:descend, %w[a a/b a/b/c], "a/b/c")
  defassert(:descend, %w[. ./a ./a/b ./a/b/c], "./a/b/c")
  defassert(:descend, %w[a/], "a/")

  def ascend(path)
    Pathname.new(path).enum_for(:ascend).map {|v| v.to_s }
  end

  defassert(:ascend, %w[/a/b/c /a/b /a /], "/a/b/c")
  defassert(:ascend, %w[a/b/c a/b a], "a/b/c")
  defassert(:ascend, %w[./a/b/c ./a/b ./a .], "./a/b/c")
  defassert(:ascend, %w[a/], "a/")

  def test_initialize
    p1 = Pathname.new('a')
    assert_equal('a', p1.to_s)
    p2 = Pathname.new(p1)
    assert_equal(p1, p2)
  end

  def test_initialize_nul
    assert_raise(ArgumentError) { Pathname.new("a\0") }
  end

  class AnotherStringLike # :nodoc:
    def initialize(s) @s = s end
    def to_str() @s end
    def ==(other) @s == other end
  end

  def test_equality
    obj = Pathname.new("a")
    str = "a"
    sym = :a
    ano = AnotherStringLike.new("a")
    assert_equal(false, obj == str)
    assert_equal(false, str == obj)
    assert_equal(false, obj == ano)
    assert_equal(false, ano == obj)
    assert_equal(false, obj == sym)
    assert_equal(false, sym == obj)

    obj2 = Pathname.new("a")
    assert_equal(true, obj == obj2)
    assert_equal(true, obj === obj2)
    assert_equal(true, obj.eql?(obj2))
  end

  def test_hashkey
    h = {}
    h[Pathname.new("a")] = 1
    h[Pathname.new("a")] = 2
    assert_equal(1, h.size)
  end

  def assert_pathname_cmp(e, s1, s2)
    p1 = Pathname.new(s1)
    p2 = Pathname.new(s2)
    r = p1 <=> p2
    assert(e == r,
      "#{p1.inspect} <=> #{p2.inspect}: <#{e}> expected but was <#{r}>")
  end
  def test_comparison
    assert_pathname_cmp( 0, "a", "a")
    assert_pathname_cmp( 1, "b", "a")
    assert_pathname_cmp(-1, "a", "b")
    ss = %w(
      a
      a/
      a/b
      a.
      a0
    )
    s1 = ss.shift
    ss.each {|s2|
      assert_pathname_cmp(-1, s1, s2)
      s1 = s2
    }
  end

  def test_comparison_string
    assert_equal(nil, Pathname.new("a") <=> "a")
    assert_equal(nil, "a" <=> Pathname.new("a"))
  end

  def pathsub(path, pat, repl) Pathname.new(path).sub(pat, repl).to_s end
  defassert(:pathsub, "a.o", "a.c", /\.c\z/, ".o")

  def pathsubext(path, repl) Pathname.new(path).sub_ext(repl).to_s end
  defassert(:pathsubext, 'a.o', 'a.c', '.o')
  defassert(:pathsubext, 'a.o', 'a.c++', '.o')
  defassert(:pathsubext, 'a.png', 'a.gif', '.png')
  defassert(:pathsubext, 'ruby.tar.bz2', 'ruby.tar.gz', '.bz2')
  defassert(:pathsubext, 'd/a.o', 'd/a.c', '.o')
  defassert(:pathsubext, 'foo', 'foo.exe', '')
  defassert(:pathsubext, 'lex.yy.o', 'lex.yy.c', '.o')
  defassert(:pathsubext, 'fooaa.o', 'fooaa', '.o')
  defassert(:pathsubext, 'd.e/aa.o', 'd.e/aa', '.o')

  def test_sub_matchdata
    result = Pathname("abc.gif").sub(/\..*/) {
      assert_not_nil($~)
      assert_equal(".gif", $~[0])
      ".png"
    }
    assert_equal("abc.png", result.to_s)
  end

  def root?(path)
    Pathname.new(path).root?
  end

  defassert(:root?, true, "/")
  defassert(:root?, true, "//")
  defassert(:root?, true, "///")
  defassert(:root?, false, "")
  defassert(:root?, false, "a")

  def test_destructive_update
    path = Pathname.new("a")
    path.to_s.replace "b"
    assert_equal(Pathname.new("a"), path)
  end

  def test_null_character
    assert_raise(ArgumentError) { Pathname.new("\0") }
  end

  def test_taint
    obj = Pathname.new("a"); assert_same(obj, obj.taint)
    obj = Pathname.new("a"); assert_same(obj, obj.untaint)

    assert_equal(false, Pathname.new("a"      )           .tainted?)
    assert_equal(false, Pathname.new("a"      )      .to_s.tainted?)
    assert_equal(true,  Pathname.new("a"      ).taint     .tainted?)
    assert_equal(true,  Pathname.new("a"      ).taint.to_s.tainted?)
    assert_equal(true,  Pathname.new("a".taint)           .tainted?)
    assert_equal(true,  Pathname.new("a".taint)      .to_s.tainted?)
    assert_equal(true,  Pathname.new("a".taint).taint     .tainted?)
    assert_equal(true,  Pathname.new("a".taint).taint.to_s.tainted?)

    str = "a"
    path = Pathname.new(str)
    str.taint
    assert_equal(false, path     .tainted?)
    assert_equal(false, path.to_s.tainted?)
  end

  def test_untaint
    obj = Pathname.new("a"); assert_same(obj, obj.untaint)

    assert_equal(false, Pathname.new("a").taint.untaint     .tainted?)
    assert_equal(false, Pathname.new("a").taint.untaint.to_s.tainted?)

    str = "a".taint
    path = Pathname.new(str)
    str.untaint
    assert_equal(true, path     .tainted?)
    assert_equal(true, path.to_s.tainted?)
  end

  def test_freeze
    obj = Pathname.new("a"); assert_same(obj, obj.freeze)

    assert_equal(false, Pathname.new("a"       )            .frozen?)
    assert_equal(false, Pathname.new("a".freeze)            .frozen?)
    assert_equal(true,  Pathname.new("a"       ).freeze     .frozen?)
    assert_equal(true,  Pathname.new("a".freeze).freeze     .frozen?)
    assert_equal(false, Pathname.new("a"       )       .to_s.frozen?)
    assert_equal(false, Pathname.new("a".freeze)       .to_s.frozen?)
    assert_equal(false, Pathname.new("a"       ).freeze.to_s.frozen?)
    assert_equal(false, Pathname.new("a".freeze).freeze.to_s.frozen?)
  end

  def test_freeze_and_taint
    obj = Pathname.new("a")
    obj.freeze
    assert_equal(false, obj.tainted?)
    assert_raise(RuntimeError) { obj.taint }

    obj = Pathname.new("a")
    obj.taint
    assert_equal(true, obj.tainted?)
    obj.freeze
    assert_equal(true, obj.tainted?)
    assert_nothing_raised { obj.taint }
  end

  def test_to_s
    str = "a"
    obj = Pathname.new(str)
    assert_equal(str, obj.to_s)
    assert_not_same(str, obj.to_s)
    assert_not_same(obj.to_s, obj.to_s)
  end

  def test_kernel_open
    count = 0
    result = Kernel.open(Pathname.new(__FILE__)) {|f|
      assert(File.identical?(__FILE__, f))
      count += 1
      2
    }
    assert_equal(1, count)
    assert_equal(2, result)
  end

  def test_each_filename
    result = []
    Pathname.new("/usr/bin/ruby").each_filename {|f| result << f }
    assert_equal(%w[usr bin ruby], result)
    assert_equal(%w[usr bin ruby], Pathname.new("/usr/bin/ruby").each_filename.to_a)
  end

  def test_kernel_pathname
    assert_equal(Pathname.new("a"), Pathname("a"))
  end

  def test_file_basename
    assert_equal("bar", File.basename(Pathname.new("foo/bar")))
  end

  def test_file_dirname
    assert_equal("foo", File.dirname(Pathname.new("foo/bar")))
  end

  def test_file_split
    assert_equal(["foo", "bar"], File.split(Pathname.new("foo/bar")))
  end

  def test_file_extname
    assert_equal(".baz", File.extname(Pathname.new("bar.baz")))
  end

  def test_file_fnmatch
    assert(File.fnmatch("*.*", Pathname.new("bar.baz")))
  end

  def test_file_join
    assert_equal("foo/bar", File.join(Pathname.new("foo"), Pathname.new("bar")))
    lambda {
      $SAFE = 1
      assert_equal("foo/bar", File.join(Pathname.new("foo"), Pathname.new("bar").taint))
    }.call
  end
end
