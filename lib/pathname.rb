# Object-Oriented Pathname Class
#
# Author:: Tanaka Akira <akr@m17n.org>

# Pathname represents a pathname which locates a file in a filesystem.
#
# Pathname is immutable.  It has no method for destructive update.
#
# pathname.rb is distributed with Ruby since 1.8.0.
class Pathname
  def initialize(path)
    @path = path.to_str.dup
    @path.freeze

    if /\0/ =~ @path
      raise ArgumentError, "pathname contains \\0: #{@path.inspect}"
    end
  end

  def ==(other)
    return false unless Pathname === other
    other.to_s == @path
  end
  alias === ==
  alias eql? ==

  def <=>(other)
    return nil unless Pathname === other
    @path.tr('/', "\0") <=> other.to_s.tr('/', "\0")
  end

  def hash
    @path.hash
  end

  def to_s
    @path.dup
  end

  # to_str is implemented for Pathname object usable with File.open, etc.
  alias to_str to_s

  def inspect
    "#<#{self.class}:#{@path}>"
  end

  # cleanpath returns clean pathname of self which is without consecutive
  # slashes and useless dots.
  #
  # If true is given as the optional argument consider_symlink,
  # symbolic links are considered.  It makes more dots are retained.
  #
  # cleanpath doesn't access actual filesystem.
  def cleanpath(consider_symlink=false)
    if consider_symlink
      cleanpath_conservative
    else
      cleanpath_aggressive
    end
  end

  def cleanpath_aggressive # :nodoc:
    # cleanpath_aggressive assumes:
    # * no symlink
    # * all pathname prefix contained in the pathname is existing directory
    return Pathname.new('') if @path == ''
    absolute = absolute?
    names = []
    @path.scan(%r{[^/]+}) {|name|
      next if name == '.'
      if name == '..'
        if names.empty?
          next if absolute
        else
          if names.last != '..'
            names.pop
            next
          end
        end
      end
      names << name
    }
    return Pathname.new(absolute ? '/' : '.') if names.empty?
    path = absolute ? '/' : ''
    path << names.join('/')
    Pathname.new(path)
  end

  def cleanpath_conservative # :nodoc:
    return Pathname.new('') if @path == ''
    names = @path.scan(%r{[^/]+})
    last_dot = names.last == '.'
    names.delete('.')
    names.shift while names.first == '..' if absolute?
    return Pathname.new(absolute? ? '/' : '.') if names.empty?
    path = absolute? ? '/' : ''
    path << names.join('/')
    if names.last != '..'
      if last_dot
        path << '/.'
      elsif %r{/\z} =~ @path
        path << '/'
      end
    end
    Pathname.new(path)
  end

  # realpath returns real pathname of self in actual filesystem.
  #
  # If false is given for the optional argument force_absolute,
  # it may return relative pathname.
  # Otherwise it returns absolute pathname.
  def realpath(force_absolute=true)
    # Check file existence at first by File.stat.
    # This test detects ELOOP.
    #
    # /tmp/a -> a
    # /tmp/b -> b/b
    # /tmp/c -> ./c
    # /tmp/d -> ../tmp/d

    File.stat(@path)

    top = %r{\A/} =~ @path ? '/' : ''
    unresolved = @path.scan(%r{[^/]+})
    resolved = []
    checked_path = {}
    
    until unresolved.empty?
      case unresolved.last
      when '.'
        unresolved.pop
      when '..'
        resolved.unshift unresolved.pop
      else
        path = top + unresolved.join('/')
        raise Errno::ELOOP.new(path) if checked_path[path]
        checked_path[path] = true
        if File.lstat(path).symlink?
          link = File.readlink(path)
          if %r{\A/} =~ link
            top = '/'
            unresolved = link.scan(%r{[^/]+})
          else
            unresolved.pop
            unresolved.concat link.scan(%r{[^/]+})
          end
        else
          resolved.unshift unresolved.pop
        end
      end
    end
    
    if resolved.empty?
      path = top.empty? ? '.' : top
    else
      path = top + resolved.join('/')
    end
    
    # Note that Dir.pwd has no symlinks.
    path = File.join(Dir.pwd, path) if %r{\A/} !~ path && force_absolute

    Pathname.new(path).cleanpath
  end

  # parent method returns parent directory, i.e. ".." is joined at last.
  def parent
    self.join('..')
  end

  # mountpoint? method returns true if self points a mountpoint.
  def mountpoint?
    begin
      stat1 = self.lstat
      stat2 = self.parent.lstat
      stat1.dev == stat2.dev && stat1.ino == stat2.ino ||
      stat1.dev != stat2.dev
    rescue Errno::ENOENT
      false
    end
  end

  # root? method is a predicate for root directory.
  # I.e. it returns true if the pathname consists of consecutive slashes.
  #
  # It doesn't access actual filesystem.
  # So it may return false for some pathnames
  # which points root such as "/usr/..".
  def root?
    %r{\A/+\z} =~ @path ? true : false
  end

  # absolute? method is a predicate for absolute pathname.
  # It returns true if self is beginning with a slash.
  def absolute?
    %r{\A/} =~ @path ? true : false
  end

  # relative? method is a predicate for relative pathname.
  # It returns true unless self is beginning with a slash.
  def relative?
    !absolute?
  end

  # each_filename iterates over self for each filename components.
  def each_filename
    @path.scan(%r{[^/]+}) { yield $& }
  end

  # Pathname#+ return new pathname which is concatenated with self and
  # an argument.
  # If the argument is absolute pathname, it is just returned.
  def +(other)
    other = Pathname.new(other) unless Pathname === other
    if other.absolute?
      other
    elsif %r{/\z} =~ @path
      Pathname.new(@path + other.to_s)
    else
      Pathname.new(@path + '/' + other.to_s)
    end
  end

  # Pathname#children returns the children of the directory as an array of
  # pathnames.  
  #
  # By default, self is prepended to each pathname in the result.
  # It is disabled if false is given for the optional argument
  # prepend_directory.
  #
  # Note that the result never contain '.' and '..' because they are not
  # child.
  #
  # This method is exist since 1.8.1.
  def children(prepend_directory=true)
    result = []
    Dir.foreach(@path) {|e|
      next if e == '.' || e == '..'
      if prepend_directory
        result << Pathname.new(File.join(@path, e))
      else
        result << Pathname.new(e)
      end
    }
    result
  end

  # Pathname#relative_path_from returns a relative path from the argument to
  # self.
  # If self is absolute, the argument must be absolute too.
  # If self is relative, the argument must be relative too.
  #
  # relative_path_from doesn't access actual filesystem.
  # It assumes no symlinks.
  #
  # ArgumentError is raised when it cannot find a relative path.
  #
  # This method is exist since 1.8.1.
  def relative_path_from(base_directory)
    if self.absolute? != base_directory.absolute?
      raise ArgumentError,
        "relative path between absolute and relative path: #{self.inspect}, #{base_directory.inspect}"
    end

    dest = []
    self.cleanpath.each_filename {|f|
      next if f == '.'
      dest << f
    }

    base = []
    base_directory.cleanpath.each_filename {|f|
      next if f == '.'
      base << f
    }

    while !base.empty? && !dest.empty? && base[0] == dest[0]
      base.shift
      dest.shift
    end

    if base.include? '..'
      raise ArgumentError, "base_directory has ..: #{base_directory.inspect}"
    end

    base.fill '..'
    relpath = base + dest
    if relpath.empty?
      Pathname.new(".")
    else
      Pathname.new(relpath.join('/'))
    end
  end

end

# IO
class Pathname
  # Pathname#each_line iterates over lines of the file.
  # It's yields String objects for each line.
  #
  # This method is exist since 1.8.1.
  def each_line(*args, &block) IO.foreach(@path, *args, &block) end

  # Pathname#foreachline is obsoleted at 1.8.1.
  #
  def foreachline(*args, &block) # compatibility to 1.8.0.  obsoleted.
    warn "Pathname#foreachline is obsoleted.  Use Pathname#each_line."
    each_line(*args, &block)
  end

  def read(*args) IO.read(@path, *args) end
  def readlines(*args) IO.readlines(@path, *args) end
  def sysopen(*args) IO.sysopen(@path, *args) end
end

# File
class Pathname
  def atime() File.atime(@path) end
  def ctime() File.ctime(@path) end
  def mtime() File.mtime(@path) end
  def chmod(mode) File.chmod(mode, @path) end
  def lchmod(mode) File.chmod(mode, @path) end
  def chown(owner, group) File.chown(owner, group, @path) end
  def lchown(owner, group) File.lchown(owner, group, @path) end
  def fnmatch(pattern, *args) File.fnmatch(pattern, @path, *args) end
  def fnmatch?(pattern, *args) File.fnmatch?(pattern, @path, *args) end
  def ftype() File.ftype(@path) end
  def link(old) File.link(old, @path) end
  def open(*args, &block) File.open(@path, *args, &block) end
  def readlink() Pathname.new(File.readlink(@path)) end
  def rename(to) File.rename(@path, to) end
  def stat() File.stat(@path) end
  def lstat() File.lstat(@path) end
  def symlink(old) File.symlink(old, @path) end
  def truncate(length) File.truncate(@path, length) end
  def utime(atime, mtime) File.utime(atime, mtime, @path) end
  def basename(*args) Pathname.new(File.basename(@path, *args)) end
  def dirname() Pathname.new(File.dirname(@path)) end
  def extname() File.extname(@path) end
  def expand_path(*args) Pathname.new(File.expand_path(@path, *args)) end
  def join(*args) Pathname.new(File.join(@path, *args)) end
  def split() File.split(@path).map {|f| Pathname.new(f) } end
end

# FileTest
class Pathname
  def blockdev?() FileTest.blockdev?(@path) end
  def chardev?() FileTest.chardev?(@path) end
  def executable?() FileTest.executable?(@path) end
  def executable_real?() FileTest.executable_real?(@path) end
  def exist?() FileTest.exist?(@path) end
  def grpowned?() FileTest.grpowned?(@path) end
  def directory?() FileTest.directory?(@path) end
  def file?() FileTest.file?(@path) end
  def pipe?() FileTest.pipe?(@path) end
  def socket?() FileTest.socket?(@path) end
  def owned?() FileTest.owned?(@path) end
  def readable?() FileTest.readable?(@path) end
  def readable_real?() FileTest.readable_real?(@path) end
  def setuid?() FileTest.setuid?(@path) end
  def setgid?() FileTest.setgid?(@path) end
  def size() FileTest.size(@path) end
  def size?() FileTest.size?(@path) end
  def sticky?() FileTest.sticky?(@path) end
  def symlink?() FileTest.symlink?(@path) end
  def writable?() FileTest.writable?(@path) end
  def writable_real?() FileTest.writable_real?(@path) end
  def zero?() FileTest.zero?(@path) end
end

# Dir
class Pathname
  def Pathname.glob(*args)
    if block_given?
      Dir.glob(*args) {|f| yield Pathname.new(f) }
    else
      Dir.glob(*args).map {|f| Pathname.new(f) }
    end
  end

  def Pathname.getwd() Pathname.new(Dir.getwd) end
  class << self; alias pwd getwd end

  # Pathname#chdir is obsoleted at 1.8.1.
  #
  def chdir(&block) # compatibility to 1.8.0.
    warn "Pathname#chdir is obsoleted.  Use Dir.chdir."
    Dir.chdir(@path, &block)
  end

  # Pathname#chroot is obsoleted at 1.8.1.
  #
  def chroot # compatibility to 1.8.0.
    warn "Pathname#chroot is obsoleted.  Use Dir.chroot."
    Dir.chroot(@path)
  end

  def rmdir() Dir.rmdir(@path) end
  def entries() Dir.entries(@path).map {|f| Pathname.new(f) } end

  # Pathname#each_entry iterates over entries of the directory.
  # It's yields Pathname objects for each entry.
  #
  # This method is exist since 1.8.1.
  def each_entry(&block) Dir.foreach(@path) {|f| yield Pathname.new(f) } end

  # Pathname#dir_foreach is obsoleted at 1.8.1.
  #
  def dir_foreach(*args, &block) # compatibility to 1.8.0.  obsoleted.
    warn "Pathname#dir_foreach is obsoleted.  Use Pathname#each_entry."
    each_entry(*args, &block)
  end

  def mkdir(*args) Dir.mkdir(@path, *args) end
  def opendir(&block) Dir.open(@path, &block) end
end

# Find
class Pathname
  def find(&block)
    require 'find'
    Find.find(@path) {|f| yield Pathname.new(f) }
  end
end

# FileUtils
class Pathname
  def mkpath
    require 'fileutils'
    FileUtils.mkpath(@path)
    nil
  end

  def rmtree
    # The name "rmtree" is borrowed from File::Path of Perl.
    # File::Path provides "mkpath" and "rmtree".
    require 'fileutils'
    FileUtils.rm_r(@path)
    nil
  end
end

# mixed
class Pathname
  def unlink()
    if FileTest.directory? @path
      Dir.unlink @path
    else
      File.unlink @path
    end
  end
  alias delete unlink

  # This method is obsoleted at 1.8.1.
  #
  def foreach(*args, &block) # compatibility to 1.8.0.  obsoleted.
    warn "Pathname#foreach is obsoleted.  Use each_line or each_entry."
    if FileTest.directory? @path
      # For polymorphism between Dir.foreach and IO.foreach,
      # Pathname#foreach doesn't yield Pathname object.
      Dir.foreach(@path, *args, &block)
    else
      IO.foreach(@path, *args, &block)
    end
  end
end

if $0 == __FILE__
  require 'test/unit'

  class PathnameTest < Test::Unit::TestCase # :nodoc:
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

    def test_syntactical
      assert_equal(true, Pathname.new("/").root?)
      assert_equal(true, Pathname.new("//").root?)
      assert_equal(true, Pathname.new("///").root?)
      assert_equal(false, Pathname.new("").root?)
      assert_equal(false, Pathname.new("a").root?)
    end

    def test_cleanpath
      assert_equal('/', Pathname.new('/').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('//').cleanpath(true).to_s)
      assert_equal('', Pathname.new('').cleanpath(true).to_s)

      assert_equal('.', Pathname.new('.').cleanpath(true).to_s)
      assert_equal('..', Pathname.new('..').cleanpath(true).to_s)
      assert_equal('a', Pathname.new('a').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('/.').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('/..').cleanpath(true).to_s)
      assert_equal('/a', Pathname.new('/a').cleanpath(true).to_s)
      assert_equal('.', Pathname.new('./').cleanpath(true).to_s)
      assert_equal('..', Pathname.new('../').cleanpath(true).to_s)
      assert_equal('a/', Pathname.new('a/').cleanpath(true).to_s)

      assert_equal('a/b', Pathname.new('a//b').cleanpath(true).to_s)
      assert_equal('a/.', Pathname.new('a/.').cleanpath(true).to_s)
      assert_equal('a/.', Pathname.new('a/./').cleanpath(true).to_s)
      assert_equal('a/..', Pathname.new('a/../').cleanpath(true).to_s)
      assert_equal('/a/.', Pathname.new('/a/.').cleanpath(true).to_s)
      assert_equal('..', Pathname.new('./..').cleanpath(true).to_s)
      assert_equal('..', Pathname.new('../.').cleanpath(true).to_s)
      assert_equal('..', Pathname.new('./../').cleanpath(true).to_s)
      assert_equal('..', Pathname.new('.././').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('/./..').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('/../.').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('/./../').cleanpath(true).to_s)
      assert_equal('/', Pathname.new('/.././').cleanpath(true).to_s)

      assert_equal('a/b/c', Pathname.new('a/b/c').cleanpath(true).to_s)
      assert_equal('b/c', Pathname.new('./b/c').cleanpath(true).to_s)
      assert_equal('a/c', Pathname.new('a/./c').cleanpath(true).to_s)
      assert_equal('a/b/.', Pathname.new('a/b/.').cleanpath(true).to_s)
      assert_equal('a/..', Pathname.new('a/../.').cleanpath(true).to_s)

      assert_equal('/a', Pathname.new('/../.././../a').cleanpath(true).to_s)
      assert_equal('a/b/../../../../c/../d',
        Pathname.new('a/b/../../../../c/../d').cleanpath(true).to_s)
    end

    def test_cleanpath_no_symlink
      assert_equal('/', Pathname.new('/').cleanpath.to_s)
      assert_equal('/', Pathname.new('//').cleanpath.to_s)
      assert_equal('', Pathname.new('').cleanpath.to_s)

      assert_equal('.', Pathname.new('.').cleanpath.to_s)
      assert_equal('..', Pathname.new('..').cleanpath.to_s)
      assert_equal('a', Pathname.new('a').cleanpath.to_s)
      assert_equal('/', Pathname.new('/.').cleanpath.to_s)
      assert_equal('/', Pathname.new('/..').cleanpath.to_s)
      assert_equal('/a', Pathname.new('/a').cleanpath.to_s)
      assert_equal('.', Pathname.new('./').cleanpath.to_s)
      assert_equal('..', Pathname.new('../').cleanpath.to_s)
      assert_equal('a', Pathname.new('a/').cleanpath.to_s)

      assert_equal('a/b', Pathname.new('a//b').cleanpath.to_s)
      assert_equal('a', Pathname.new('a/.').cleanpath.to_s)
      assert_equal('a', Pathname.new('a/./').cleanpath.to_s)
      assert_equal('.', Pathname.new('a/../').cleanpath.to_s)
      assert_equal('/a', Pathname.new('/a/.').cleanpath.to_s)
      assert_equal('..', Pathname.new('./..').cleanpath.to_s)
      assert_equal('..', Pathname.new('../.').cleanpath.to_s)
      assert_equal('..', Pathname.new('./../').cleanpath.to_s)
      assert_equal('..', Pathname.new('.././').cleanpath.to_s)
      assert_equal('/', Pathname.new('/./..').cleanpath.to_s)
      assert_equal('/', Pathname.new('/../.').cleanpath.to_s)
      assert_equal('/', Pathname.new('/./../').cleanpath.to_s)
      assert_equal('/', Pathname.new('/.././').cleanpath.to_s)

      assert_equal('a/b/c', Pathname.new('a/b/c').cleanpath.to_s)
      assert_equal('b/c', Pathname.new('./b/c').cleanpath.to_s)
      assert_equal('a/c', Pathname.new('a/./c').cleanpath.to_s)
      assert_equal('a/b', Pathname.new('a/b/.').cleanpath.to_s)
      assert_equal('.', Pathname.new('a/../.').cleanpath.to_s)

      assert_equal('/a', Pathname.new('/../.././../a').cleanpath.to_s)
      assert_equal('../../d', Pathname.new('a/b/../../../../c/../d').cleanpath.to_s)
    end

    def test_destructive_update
      path = Pathname.new("a")
      path.to_s.replace "b"
      assert_equal(Pathname.new("a"), path)
    end

    def test_null_character
      assert_raises(ArgumentError) { Pathname.new("\0") }
    end

    def assert_relpath(result, dest, base)
      assert_equal(Pathname.new(result),
        Pathname.new(dest).relative_path_from(Pathname.new(base)))
    end

    def assert_relpath_err(dest, base)
      assert_raises(ArgumentError) {
        Pathname.new(dest).relative_path_from(Pathname.new(base))
      }
    end

    def test_relative_path_from
      assert_relpath("../a", "a", "b")
      assert_relpath("../a", "a", "b/")
      assert_relpath("../a", "a/", "b")
      assert_relpath("../a", "a/", "b/")
      assert_relpath("../a", "/a", "/b")
      assert_relpath("../a", "/a", "/b/")
      assert_relpath("../a", "/a/", "/b")
      assert_relpath("../a", "/a/", "/b/")

      assert_relpath("../b", "a/b", "a/c")
      assert_relpath("../a", "../a", "../b")

      assert_relpath("a", "a", ".")
      assert_relpath("..", ".", "a")

      assert_relpath(".", ".", ".")
      assert_relpath(".", "..", "..")
      assert_relpath("..", "..", ".")

      assert_relpath("c/d", "/a/b/c/d", "/a/b")
      assert_relpath("../..", "/a/b", "/a/b/c/d")
      assert_relpath("../../../../e", "/e", "/a/b/c/d")
      assert_relpath("../b/c", "a/b/c", "a/d")

      assert_relpath("../a", "/../a", "/b")
      assert_relpath("../../a", "../a", "b")
      assert_relpath(".", "/a/../../b", "/b")
      assert_relpath("..", "a/..", "a")
      assert_relpath(".", "a/../b", "b")

      assert_relpath("a", "a", "b/..")
      assert_relpath("b/c", "b/c", "b/..")

      assert_relpath_err("/", ".")
      assert_relpath_err(".", "/")
      assert_relpath_err("a", "..")
      assert_relpath_err(".", "..")
    end

  end
end
