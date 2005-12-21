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
# difference.  *All* functionality from File, FileTest, and some from Dir and
# FileUtils is included, in an unsurprising way.  It is essentially a facade for
# all of these, and more.
#
# == Examples
#
# === Example 1: Using Pathname
#
#   require 'pathname'
#   p = Pathname.new("/usr/bin/ruby")
#   size = p.size              # 27662
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
#   size = File.size(p)        # 27662
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
# is.  Except for #mountpoint?, #children, and #realpath, they don't access the
# filesystem.
#
# - +
# - #join
# - #parent
# - #root?
# - #absolute?
# - #relative?
# - #relative_path_from
# - #each_filename
# - #cleanpath
# - #realpath
# - #children
# - #mountpoint?
#
# === File status predicate methods
#
# These methods are a facade for FileTest:
# - #blockdev?
# - #chardev?
# - #directory?
# - #executable?
# - #executable_real?
# - #exist?
# - #file?
# - #grpowned?
# - #owned?
# - #pipe?
# - #readable?
# - #readable_real?
# - #setgid?
# - #setuid?
# - #size
# - #size?
# - #socket?
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
#
# == Method documentation
#
# As the above section shows, most of the methods in Pathname are facades.  The
# documentation for these methods generally just says, for instance, "See
# FileTest.writable?", as you should be familiar with the original method
# anyway, and its documentation (e.g. through +ri+) will contain more
# information.  In some cases, a brief description will follow.
#
class Pathname
  #
  # Create a Pathname object from the given String (or String-like object).
  # If +path+ contains a NUL character (<tt>\0</tt>), an ArgumentError is raised.
  #
  def initialize(path)
    path = path.to_str if path.respond_to? :to_str
    @path = path.dup

    if /\0/ =~ @path
      raise ArgumentError, "pathname contains \\0: #{@path.inspect}"
    end

    self.taint if @path.tainted?
  end

  def freeze() super; @path.freeze; self end
  def taint() super; @path.taint; self end
  def untaint() super; @path.untaint; self end

  #
  # Compare this pathname with +other+.  The comparison is string-based.
  # Be aware that two different paths (<tt>foo.txt</tt> and <tt>./foo.txt</tt>)
  # can refer to the same file.
  #
  def ==(other)
    return false unless Pathname === other
    other.to_s == @path
  end
  alias === ==
  alias eql? ==

  # Provides for comparing pathnames, case-sensitively.
  def <=>(other)
    return nil unless Pathname === other
    @path.tr('/', "\0") <=> other.to_s.tr('/', "\0")
  end

  def hash # :nodoc:
    @path.hash
  end

  # Return the path as a String.
  def to_s
    @path.dup
  end

  # to_str is implemented so Pathname objects are usable with File.open, etc.
  alias to_str to_s

  def inspect # :nodoc:
    "#<#{self.class}:#{@path}>"
  end

  #
  # Returns clean pathname of +self+ with consecutive slashes and useless dots
  # removed.  The filesystem is not accessed.
  #
  # If +consider_symlink+ is +true+, then a more conservative algorithm is used
  # to avoid breaking symbolic linkages.  This may retain more <tt>..</tt>
  # entries than absolutely necessary, but without accessing the filesystem,
  # this can't be avoided.  See #realpath.
  #
  def cleanpath(consider_symlink=false)
    if consider_symlink
      cleanpath_conservative
    else
      cleanpath_aggressive
    end
  end

  #
  # Clean the path simply by resolving and removing excess "." and ".." entries.
  # Nothing more, nothing less.
  #
  def cleanpath_aggressive
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
  private :cleanpath_aggressive

  def cleanpath_conservative
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
  private :cleanpath_conservative

  #
  # Returns a real (absolute) pathname of +self+ in the actual filesystem.
  # The real pathname doesn't contain symlinks or useless dots.
  #
  # No arguments should be given; the old behaviour is *obsoleted*. 
  #
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

  # #parent returns the parent directory.
  #
  # This is same as <tt>self + '..'</tt>.
  def parent
    self + '..'
  end

  # #mountpoint? returns +true+ if <tt>self</tt> points to a mountpoint.
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

  #
  # #root? is a predicate for root directories.  I.e. it returns +true+ if the
  # pathname consists of consecutive slashes.
  #
  # It doesn't access actual filesystem.  So it may return +false+ for some
  # pathnames which points to roots such as <tt>/usr/..</tt>.
  #
  def root?
    %r{\A/+\z} =~ @path ? true : false
  end

  # Predicate method for testing whether a path is absolute.
  # It returns +true+ if the pathname begins with a slash.
  def absolute?
    %r{\A/} =~ @path ? true : false
  end

  # The opposite of #absolute?
  def relative?
    !absolute?
  end

  #
  # Iterates over each component of the path.
  #
  #   Pathname.new("/usr/bin/ruby").each_filename {|filename| ... }
  #     # yields "usr", "bin", and "ruby".
  #
  def each_filename # :yield: s
    @path.scan(%r{[^/]+}) { yield $& }
  end

  #
  # Pathname#+ appends a pathname fragment to this one to produce a new Pathname
  # object.
  #
  #   p1 = Pathname.new("/usr")      # Pathname:/usr
  #   p2 = p1 + "bin/ruby"           # Pathname:/usr/bin/ruby
  #   p3 = p1 + "/etc/passwd"        # Pathname:/etc/passwd
  #
  # This method doesn't access the file system; it is pure string manipulation. 
  #
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

  #
  # Pathname#join joins pathnames.
  #
  # <tt>path0.join(path1, ..., pathN)</tt> is the same as
  # <tt>path0 + path1 + ... + pathN</tt>.
  #
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

  #
  # Returns the children of the directory (files and subdirectories, not
  # recursive) as an array of Pathname objects.  By default, the returned
  # pathnames will have enough information to access the files.  If you set
  # +with_directory+ to +false+, then the returned pathnames will contain the
  # filename only.
  #
  # For example:
  #   p = Pathname("/usr/lib/ruby/1.8")
  #   p.children
  #       # -> [ Pathname:/usr/lib/ruby/1.8/English.rb,
  #              Pathname:/usr/lib/ruby/1.8/Env.rb,
  #              Pathname:/usr/lib/ruby/1.8/abbrev.rb, ... ]
  #   p.children(false)
  #       # -> [ Pathname:English.rb, Pathname:Env.rb, Pathname:abbrev.rb, ... ]
  #
  # Note that the result never contain the entries <tt>.</tt> and <tt>..</tt> in
  # the directory because they are not children.
  #
  # This method has existed since 1.8.1.
  #
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

  #
  # #relative_path_from returns a relative path from the argument to the
  # receiver.  If +self+ is absolute, the argument must be absolute too.  If
  # +self+ is relative, the argument must be relative too.
  #
  # #relative_path_from doesn't access the filesystem.  It assumes no symlinks.
  #
  # ArgumentError is raised when it cannot find a relative path.
  #
  # This method has existed since 1.8.1.
  #
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
  #
  # #each_line iterates over the line in the file.  It yields a String object
  # for each line.
  #
  # This method has existed since 1.8.1.
  #
  def each_line(*args, &block) # :yield: line
    IO.foreach(@path, *args, &block)
  end

  # Pathname#foreachline is *obsoleted* at 1.8.1.  Use #each_line.
  def foreachline(*args, &block)
    warn "Pathname#foreachline is obsoleted.  Use Pathname#each_line."
    each_line(*args, &block)
  end

  # See <tt>IO.read</tt>.  Returns all the bytes from the file, or the first +N+
  # if specified.
  def read(*args) IO.read(@path, *args) end

  # See <tt>IO.readlines</tt>.  Returns all the lines from the file.
  def readlines(*args) IO.readlines(@path, *args) end

  # See <tt>IO.sysopen</tt>.
  def sysopen(*args) IO.sysopen(@path, *args) end
end


class Pathname    # * File *

  # See <tt>File.atime</tt>.  Returns last access time.
  def atime() File.atime(@path) end

  # See <tt>File.ctime</tt>.  Returns last (directory entry, not file) change time.
  def ctime() File.ctime(@path) end

  # See <tt>File.mtime</tt>.  Returns last modification time.
  def mtime() File.mtime(@path) end

  # See <tt>File.chmod</tt>.  Changes permissions.
  def chmod(mode) File.chmod(mode, @path) end

  # See <tt>File.lchmod</tt>.
  def lchmod(mode) File.lchmod(mode, @path) end

  # See <tt>File.chown</tt>.  Change owner and group of file.
  def chown(owner, group) File.chown(owner, group, @path) end

  # See <tt>File.lchown</tt>.
  def lchown(owner, group) File.lchown(owner, group, @path) end

  # See <tt>File.fnmatch</tt>.  Return +true+ if the receiver matches the given
  # pattern.
  def fnmatch(pattern, *args) File.fnmatch(pattern, @path, *args) end

  # See <tt>File.fnmatch?</tt> (same as #fnmatch).
  def fnmatch?(pattern, *args) File.fnmatch?(pattern, @path, *args) end

  # See <tt>File.ftype</tt>.  Returns "type" of file ("file", "directory",
  # etc).
  def ftype() File.ftype(@path) end

  # See <tt>File.link</tt>.  Creates a hard link.
  def make_link(old) File.link(old, @path) end

  # See <tt>File.open</tt>.  Opens the file for reading or writing.
  def open(*args, &block) # :yield: file
    File.open(@path, *args, &block)
  end

  # See <tt>File.readlink</tt>.  Read symbolic link.
  def readlink() Pathname.new(File.readlink(@path)) end

  # See <tt>File.rename</tt>.  Rename the file.
  def rename(to) File.rename(@path, to) end

  # See <tt>File.stat</tt>.  Returns a <tt>File::Stat</tt> object.
  def stat() File.stat(@path) end

  # See <tt>File.lstat</tt>.
  def lstat() File.lstat(@path) end

  # See <tt>File.symlink</tt>.  Creates a symbolic link.
  def make_symlink(old) File.symlink(old, @path) end

  # See <tt>File.truncate</tt>.  Truncate the file to +length+ bytes.
  def truncate(length) File.truncate(@path, length) end

  # See <tt>File.utime</tt>.  Update the access and modification times.
  def utime(atime, mtime) File.utime(atime, mtime, @path) end

  # See <tt>File.basename</tt>.  Returns the last component of the path.
  def basename(*args) Pathname.new(File.basename(@path, *args)) end

  # See <tt>File.dirname</tt>.  Returns all but the last component of the path.
  def dirname() Pathname.new(File.dirname(@path)) end

  # See <tt>File.extname</tt>.  Returns the file's extension.
  def extname() File.extname(@path) end

  # See <tt>File.expand_path</tt>.
  def expand_path(*args) Pathname.new(File.expand_path(@path, *args)) end

  # See <tt>File.split</tt>.  Returns the #dirname and the #basename in an
  # Array.
  def split() File.split(@path).map {|f| Pathname.new(f) } end

  # Pathname#link is confusing and *obsoleted* because the receiver/argument
  # order is inverted to corresponding system call.
  def link(old)
    warn 'Pathname#link is obsoleted.  Use Pathname#make_link.'
    File.link(old, @path)
  end

  # Pathname#symlink is confusing and *obsoleted* because the receiver/argument
  # order is inverted to corresponding system call.
  def symlink(old)
    warn 'Pathname#symlink is obsoleted.  Use Pathname#make_symlink.'
    File.symlink(old, @path)
  end
end


class Pathname    # * FileTest *

  # See <tt>FileTest.blockdev?</tt>.
  def blockdev?() FileTest.blockdev?(@path) end

  # See <tt>FileTest.chardev?</tt>.
  def chardev?() FileTest.chardev?(@path) end

  # See <tt>FileTest.executable?</tt>.
  def executable?() FileTest.executable?(@path) end

  # See <tt>FileTest.executable_real?</tt>.
  def executable_real?() FileTest.executable_real?(@path) end

  # See <tt>FileTest.exist?</tt>.
  def exist?() FileTest.exist?(@path) end

  # See <tt>FileTest.grpowned?</tt>.
  def grpowned?() FileTest.grpowned?(@path) end

  # See <tt>FileTest.directory?</tt>.
  def directory?() FileTest.directory?(@path) end

  # See <tt>FileTest.file?</tt>.
  def file?() FileTest.file?(@path) end

  # See <tt>FileTest.pipe?</tt>.
  def pipe?() FileTest.pipe?(@path) end

  # See <tt>FileTest.socket?</tt>.
  def socket?() FileTest.socket?(@path) end

  # See <tt>FileTest.owned?</tt>.
  def owned?() FileTest.owned?(@path) end

  # See <tt>FileTest.readable?</tt>.
  def readable?() FileTest.readable?(@path) end

  # See <tt>FileTest.readable_real?</tt>.
  def readable_real?() FileTest.readable_real?(@path) end

  # See <tt>FileTest.setuid?</tt>.
  def setuid?() FileTest.setuid?(@path) end

  # See <tt>FileTest.setgid?</tt>.
  def setgid?() FileTest.setgid?(@path) end

  # See <tt>FileTest.size</tt>.
  def size() FileTest.size(@path) end

  # See <tt>FileTest.size?</tt>.
  def size?() FileTest.size?(@path) end

  # See <tt>FileTest.sticky?</tt>.
  def sticky?() FileTest.sticky?(@path) end

  # See <tt>FileTest.symlink?</tt>.
  def symlink?() FileTest.symlink?(@path) end

  # See <tt>FileTest.writable?</tt>.
  def writable?() FileTest.writable?(@path) end

  # See <tt>FileTest.writable_real?</tt>.
  def writable_real?() FileTest.writable_real?(@path) end

  # See <tt>FileTest.zero?</tt>.
  def zero?() FileTest.zero?(@path) end
end


class Pathname    # * Dir *
  # See <tt>Dir.glob</tt>.  Returns or yields Pathname objects.
  def Pathname.glob(*args) # :yield: p
    if block_given?
      Dir.glob(*args) {|f| yield Pathname.new(f) }
    else
      Dir.glob(*args).map {|f| Pathname.new(f) }
    end
  end

  # See <tt>Dir.getwd</tt>.  Returns the current working directory as a Pathname.
  def Pathname.getwd() Pathname.new(Dir.getwd) end
  class << self; alias pwd getwd end

  # Pathname#chdir is *obsoleted* at 1.8.1.
  def chdir(&block)
    warn "Pathname#chdir is obsoleted.  Use Dir.chdir."
    Dir.chdir(@path, &block)
  end

  # Pathname#chroot is *obsoleted* at 1.8.1.
  def chroot
    warn "Pathname#chroot is obsoleted.  Use Dir.chroot."
    Dir.chroot(@path)
  end

  # Return the entries (files and subdirectories) in the directory, each as a
  # Pathname object.
  def entries() Dir.entries(@path).map {|f| Pathname.new(f) } end

  # Iterates over the entries (files and subdirectories) in the directory.  It
  # yields a Pathname object for each entry.
  #
  # This method has existed since 1.8.1.
  def each_entry(&block) # :yield: p
    Dir.foreach(@path) {|f| yield Pathname.new(f) }
  end

  # Pathname#dir_foreach is *obsoleted* at 1.8.1.
  def dir_foreach(*args, &block)
    warn "Pathname#dir_foreach is obsoleted.  Use Pathname#each_entry."
    each_entry(*args, &block)
  end

  # See <tt>Dir.mkdir</tt>.  Create the referenced directory.
  def mkdir(*args) Dir.mkdir(@path, *args) end

  # See <tt>Dir.rmdir</tt>.  Remove the referenced directory.
  def rmdir() Dir.rmdir(@path) end

  # See <tt>Dir.open</tt>.
  def opendir(&block) # :yield: dir
    Dir.open(@path, &block)
  end
end


class Pathname    # * Find *
  #
  # Pathname#find is an iterator to traverse a directory tree in a depth first
  # manner.  It yields a Pathname for each file under "this" directory.
  #
  # Since it is implemented by <tt>find.rb</tt>, <tt>Find.prune</tt> can be used
  # to control the traverse.
  #
  # If +self+ is <tt>.</tt>, yielded pathnames begin with a filename in the
  # current directory, not <tt>./</tt>.
  #
  def find(&block) # :yield: p
    require 'find'
    if @path == '.'
      Find.find(@path) {|f| yield Pathname.new(f.sub(%r{\A\./}, '')) }
    else
      Find.find(@path) {|f| yield Pathname.new(f) }
    end
  end
end


class Pathname    # * FileUtils *
  # See <tt>FileUtils.mkpath</tt>.  Creates a full path, including any
  # intermediate directories that don't yet exist.
  def mkpath
    require 'fileutils'
    FileUtils.mkpath(@path)
    nil
  end

  # See <tt>FileUtils.rm_r</tt>.  Deletes a directory and all beneath it.
  def rmtree
    # The name "rmtree" is borrowed from File::Path of Perl.
    # File::Path provides "mkpath" and "rmtree".
    require 'fileutils'
    FileUtils.rm_r(@path)
    nil
  end
end


class Pathname    # * mixed *
  # Removes a file or directory, using <tt>File.unlink</tt> or
  # <tt>Dir.unlink</tt> as necessary.
  def unlink()
    begin
      Dir.unlink @path
    rescue Errno::ENOTDIR
      File.unlink @path
    end
  end
  alias delete unlink

  # This method is *obsoleted* at 1.8.1.  Use #each_line or #each_entry.
  def foreach(*args, &block)
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
    def test_initialize
      p1 = Pathname.new('a')
      assert_equal('a', p1.to_s)
      p2 = Pathname.new(p1)
      assert_equal(p1, p2)
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
      assert_raise(ArgumentError) { Pathname.new("\0") }
    end

    def assert_relpath(result, dest, base)
      assert_equal(Pathname.new(result),
        Pathname.new(dest).relative_path_from(Pathname.new(base)))
    end

    def assert_relpath_err(dest, base)
      assert_raise(ArgumentError) {
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
      assert_pathname_plus('../..', '..', '..')
      assert_pathname_plus('/c', '/', '../c')
      assert_pathname_plus('c', 'a', '../c')
      assert_pathname_plus('a/c', 'a/b', '../c')
      assert_pathname_plus('../../c', '..', '../c')
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
  end
end
