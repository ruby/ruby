#
# = pathname.rb
#
# Object-Oriented Pathname Class
#
# Author:: Tanaka Akira <akr@m17n.org>
# Documentation:: Author and Gavin Sinclair
#
# For documentation, see class Pathname.
#
# <tt>pathname.rb</tt> is distributed with Ruby since 1.8.0.
#

#
# == Pathname
#
# Pathname represents a pathname which locates a file in a filesystem.
# It supports only Unix style pathnames.  It does not represent the file
# itself.  A Pathname can be relative or absolute.  It's not until you try to
# reference the file that it even matters whether the file exists or not.
#
# Pathname is immutable.  It has no method for destructive update.
#
# The value of this class is to manipulate file path information in a neater
# way than standard Ruby provides.  The examples below demonstrate the
# difference.  *All* functionality from File, FileTest, +ftools+ and FileUtils
# is included, in an unsurprising way.  It is essentially a facade for all of
# these, and more.
#
# == Examples
#
# === Example 1: Using Pathname
#
#   require 'pathname'
#   p = Pathname.new("/usr/bin/ruby")
#   size = p.size              # XXX
#   isdir = p.directory?       # false
#   dir  = p.dirname           # Pathname:/usr/bin
#   base = p.basename          # Pathname:ruby
#   dir, base = p.split        # [Pathname:/usr/bin, Pathname:ruby]
#   data = p.read
#   p.open { |f| _ } 
#   p.each_line { |line| _ }
#
# === Example 2: Using standard Ruby
#
#   p = "/usr/bin/ruby"
#   size = File.size(p)        # XXX
#   isdir = File.directory?(p) # false
#   dir  = File.dirname(p)     # "/usr/bin"
#   base = File.basename(p)    # "ruby"
#   dir, base = File.split(p)  # ["/usr/bin", "ruby"]
#   data = File.read(p)
#   File.open(p) { |f| _ } 
#   File.foreach(p) { |line| _ }
#
# === Example 3: Special features
#
#   p1 = Pathname.new("/usr/lib")   # Pathname:/usr/lib
#   p2 = p1 + "ruby/1.8"            # Pathname:/usr/lib/ruby/1.8
#   p3 = p1.parent                  # Pathname:/usr
#   p4 = p2.relative_path_from(p3)  # Pathname:lib/ruby/1.8
#   pwd = Pathname.pwd              # Pathname:/home/gavin
#   pwd.absolute?                   # true
#   p5 = Pathname.new "."           # Pathname:.
#   p5 = p5 + "music/../articles"   # Pathname:music/../articles
#   p5.cleanpath                    # Pathname:articles
#   p5.realpath                     # Pathname:/home/gavin/articles
#   p5.children                     # [Pathname:/home/gavin/articles/linux, ...]
# 
# == Breakdown of functionality
#
# === Core methods
#
# These methods are effectively manipulating a String, because that's all a path
# is.  They (mostly) don't access the filesystem.
#
# - #cleanpath
# - #realpath (accesses filesystem)
# - #parent
# - #mountpoint?
# - #root?
# - #absolute?
# - #relative?
# - #each_filename
# - #+
# - #join
# - #children
# - #relative_path_from
#
# === File status predicate methods
#
# These methods are a facade for FileTest:
# - #blockdev?
# - #chardev?
# - #executable?
# - #executable_real?
# - #exist?
# - #grpowned?
# - #directory?
# - #file?
# - #pipe?
# - #socket?
# - #owned?
# - #readable?
# - #readable_real?
# - #setuid?
# - #setgid?
# - #size
# - #size?
# - #sticky?
# - #symlink?
# - #writable?
# - #writable_real?
# - #zero?
#
# === File property and manipulation methods
#
# These methods are a facade for File:
# - #atime
# - #ctime
# - #mtime
# - #chmod(mode)
# - #lchmod(mode)
# - #chown(owner, group)
# - #lchown(owner, group)
# - #fnmatch(pattern, *args)
# - #fnmatch?(pattern, *args)
# - #ftype
# - #make_link(old)
# - #open(*args, &block)
# - #readlink
# - #rename(to)
# - #stat
# - #lstat
# - #make_symlink(old)
# - #truncate(length)
# - #utime(atime, mtime)
# - #basename(*args)
# - #dirname
# - #extname
# - #expand_path(*args)
# - #split
#
# === Directory methods
#
# These methods are a facade for Dir:
# - Pathname.glob(*args)
# - Pathname.getwd / Pathname.pwd
# - #rmdir
# - #entries
# - #each_entry(&block)
# - #mkdir(*args)
# - #opendir(*args)
#
# === IO
#
# These methods are a facade for IO:
# - #each_line(*args, &block)
# - #read(*args)
# - #readlines(*args)
# - #sysopen(*args)
#
# === Utilities
#
# These methods are a mixture of Find, FileUtils, and others:
# - #find(&block)
# - #mkpath
# - #rmtree
# - #unlink / #delete
#
class Pathname
  #
  # Create a Pathname object from the given String (or String-like object).
  # If +path+ contains a NUL character ("\0"), an ArgumentError is raised.
  #
  def initialize(path)
    @path = path.to_str.dup
    @path.freeze

    if /\0/ =~ @path
      raise ArgumentError, "pathname contains \\0: #{@path.inspect}"
    end
  end

  #
  # Compare this pathname with +other+.  The comparison is string-based.
  # Be aware that two different paths ("foo.txt" and "./foo.txt") can refer to
  # the same file.
  #
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

  # realpath returns a real pathname of self in actual filesystem.
  # The real pathname doesn't contain a symlink and useless dots.
  #
  # It returns absolute pathname.
  def realpath(*args)
    unless args.empty?
      warn "The argument for Pathname#realpath is obsoleted."
    end
    force_absolute = args.fetch(0, true)

    if %r{\A/} =~ @path
      top = '/'
      unresolved = @path.scan(%r{[^/]+})
    elsif force_absolute
      # Although POSIX getcwd returns a pathname which contains no symlink,
      # 4.4BSD-Lite2 derived getcwd may return the environment variable $PWD
      # which may contain a symlink.
      # So the return value of Dir.pwd should be examined.
      top = '/'
      unresolved = Dir.pwd.scan(%r{[^/]+}) + @path.scan(%r{[^/]+})
    else
      top = ''
      unresolved = @path.scan(%r{[^/]+})
    end
    resolved = []

    until unresolved.empty?
      case unresolved.last
      when '.'
        unresolved.pop
      when '..'
        resolved.unshift unresolved.pop
      else
        loop_check = {}
        while (stat = File.lstat(path = top + unresolved.join('/'))).symlink?
          symlink_id = "#{stat.dev}:#{stat.ino}"
          raise Errno::ELOOP.new(path) if loop_check[symlink_id]
          loop_check[symlink_id] = true
          if %r{\A/} =~ (link = File.readlink(path))
            top = '/'
            unresolved = link.scan(%r{[^/]+})
          else
            unresolved[-1,1] = link.scan(%r{[^/]+})
          end
        end
        next if (filename = unresolved.pop) == '.'
        if filename != '..' && resolved.first == '..'
          resolved.shift
        else
          resolved.unshift filename
        end
      end
    end

    if top == '/'
      resolved.shift while resolved[0] == '..'
    end
    
    if resolved.empty?
      Pathname.new(top.empty? ? '.' : '/')
    else
      Pathname.new(top + resolved.join('/'))
    end
  end

  # parent method returns parent directory.
  #
  # This is same as self + '..'.
  def parent
    self + '..'
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

  # Pathname#+ concatenates self and an argument.
  # I.e. a result is basically same as the argument but the base directory 
  # is changed to self if the argument is relative.
  #
  # Pathname#+ doesn't access actual filesystem.
  def +(other)
    other = Pathname.new(other) unless Pathname === other

    return other if other.absolute?

    path1 = @path
    path2 = other.to_s
    while m2 = %r{\A\.\.(?:/+|\z)}.match(path2) and
          m1 = %r{(\A|/+)([^/]+)\z}.match(path1) and
          %r{\A(?:\.|\.\.)\z} !~ m1[2]
      path1 = m1[1].empty? ? '.' : '/' if (path1 = m1.pre_match).empty?
      path2 = '.' if (path2 = m2.post_match).empty?
    end
    if %r{\A/+\z} =~ path1
      while m2 = %r{\A\.\.(?:/+|\z)}.match(path2)
        path2 = '.' if (path2 = m2.post_match).empty?
      end
    end

    return Pathname.new(path2) if path1 == '.'
    return Pathname.new(path1) if path2 == '.'

    if %r{/\z} =~ path1
      Pathname.new(path1 + path2)
    else
      Pathname.new(path1 + '/' + path2)
    end
  end

  # Pathname#join joins pathnames.
  #
  # path0.join(path1, ... pathN) is same as path0 + path1 + ... + pathN.
  def join(*args)
    args.unshift self
    result = args.pop
    result = Pathname.new(result) unless Pathname === result
    return result if result.absolute?
    args.reverse_each {|arg|
      arg = Pathname.new(arg) unless Pathname === arg
      result = arg + result
      return result if result.absolute?
    }
    result
  end

  # Pathname#children returns the children of the directory as an array of
  # pathnames.  
  #
  # By default, the returned pathname can be used to access the corresponding
  # file in the directory.
  # This is because the pathname contains self as a prefix unless self is `.'.
  #
  # If false is given for the optional argument `with_directory',
  # just filenames of children is returned.
  # In this case, the returned pathname cannot be used directly to access the
  # corresponding file when self doesn't point working directory.
  #
  # Note that the result never contain the entry `.' and `..' in the directory
  # because they are not child.
  #
  # This method is exist since 1.8.1.
  def children(with_directory=true)
    with_directory = false if @path == '.'
    result = []
    Dir.foreach(@path) {|e|
      next if e == '.' || e == '..'
      if with_directory
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


class Pathname    # * IO *
  # Pathname#each_line iterates over lines of the file.
  # It's yields a String object for each line.
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


class Pathname    # * File *
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
  def make_link(old) File.link(old, @path) end
  def open(*args, &block) File.open(@path, *args, &block) end
  def readlink() Pathname.new(File.readlink(@path)) end
  def rename(to) File.rename(@path, to) end
  def stat() File.stat(@path) end
  def lstat() File.lstat(@path) end
  def make_symlink(old) File.symlink(old, @path) end
  def truncate(length) File.truncate(@path, length) end
  def utime(atime, mtime) File.utime(atime, mtime, @path) end
  def basename(*args) Pathname.new(File.basename(@path, *args)) end
  def dirname() Pathname.new(File.dirname(@path)) end
  def extname() File.extname(@path) end
  def expand_path(*args) Pathname.new(File.expand_path(@path, *args)) end
  def split() File.split(@path).map {|f| Pathname.new(f) } end

  # Pathname#link is confusing and obsoleted because the receiver/argument
  # order is inverted to corresponding system call.
  def link(old)
    warn 'Pathname#link is obsoleted.  Use Pathname#make_link.'
    File.link(old, @path)
  end

  # Pathname#symlink is confusing and obsoleted because the receiver/argument
  # order is inverted to corresponding system call.
  def symlink(old)
    warn 'Pathname#symlink is obsoleted.  Use Pathname#make_symlink.'
    File.symlink(old, @path)
  end
end


class Pathname    # * FileTest *
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


class Pathname    # * Dir *
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


class Pathname    # * Find *
  # Pathname#find is a iterator to traverse directory tree in depth first
  # manner.  It yields a pathname for each file under the directory which
  # is pointed by self.
  #
  # Since it is implemented by find.rb, Find.prune can be used to control the
  # traverse.
  #
  # If self is `.', yielded pathnames begin with a filename in the current
  # directory, not `./'.
  def find(&block)
    require 'find'
    if @path == '.'
      Find.find(@path) {|f| yield Pathname.new(f.sub(%r{\A\./}, '')) }
    else
      Find.find(@path) {|f| yield Pathname.new(f) }
    end
  end
end


class Pathname    # * FileUtils *
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


class Pathname    # * mixed *
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

    def assert_pathname_plus(a, b, c)
      a = Pathname.new(a)
      b = Pathname.new(b)
      c = Pathname.new(c)
      d = b + c
      assert(a == d,
        "#{b.inspect} + #{c.inspect}: #{a.inspect} expected but was #{d.inspect}")
    end

    def test_plus
      assert_pathname_plus('a/b', 'a', 'b')
      assert_pathname_plus('a', 'a', '.')
      assert_pathname_plus('b', '.', 'b')
      assert_pathname_plus('.', '.', '.')
      assert_pathname_plus('/b', 'a', '/b')

      assert_pathname_plus('/', '/', '..')
      assert_pathname_plus('.', 'a', '..')
      assert_pathname_plus('a', 'a/b', '..')
      assert_pathname_plus('/c', '/', '../c')
      assert_pathname_plus('c', 'a', '../c')
      assert_pathname_plus('a/c', 'a/b', '../c')
    end
  end
end
