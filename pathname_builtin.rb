# frozen_string_literal: true
#
# A \Pathname object contains a string directory path or filepath;
# it does not represent a corresponding actual file or directory
# -- which in fact may or may not exist.
#
# A \Pathname object is immutable (except for method #freeze).
#
# A pathname may be relative or absolute:
#
#   Pathname.new('lib')            # => #<Pathname:lib>
#   Pathname.new('/usr/local/bin') # => #<Pathname:/usr/local/bin>
#
# == About the Examples
#
# Many examples here use these variables:
#
#  :include: doc/examples/files.rdoc
#
# == Convenience Methods
#
# The class provides *all* functionality from class File and module FileTest,
# along with some functionality from class Dir and module FileUtils.
#
# Here's an example string path and corresponding \Pathname object:
#
#   path = 'lib/fileutils.rb'
#   pn = Pathname.new(path) # => #<Pathname:lib/fileutils.rb>
#
# Each of these method pairs (\Pathname vs. \File) gives exactly the same result:
#
#   pn.size               # => 83777
#   File.size(path)       # => 83777
#
#   pn.directory?         # => false
#   File.directory?(path) # => false
#
#   pn.read.size          # => 81074
#   File.read(path).size# # => 81074
#
# Each of these method pairs gives similar results,
# but each \Pathname method returns a more versatile \Pathname object,
# instead of a string:
#
#   pn.dirname          # => #<Pathname:lib>
#   File.dirname(path)  # => "lib"
#
#   pn.basename         # => #<Pathname:fileutils.rb>
#   File.basename(path) # => "fileutils.rb"
#
#   pn.split            # => [#<Pathname:lib>, #<Pathname:fileutils.rb>]
#   File.split(path)    # => ["lib", "fileutils.rb"]
#
# Each of these methods takes a block:
#
#   pn.open do |file|
#     p file
#   end
#   File.open(path) do |file|
#     p file
#   end
#
# The outputs for each:
#
#   #<File:lib/fileutils.rb (closed)>
#   #<File:lib/fileutils.rb (closed)>
#
# Each of these methods takes a block:
#
#   pn.each_line do |line|
#     p line
#     break
#   end
#   File.foreach(path) do |line|
#     p line
#     break
#   end
#
# The outputs for each:
#
#   "# frozen_string_literal: true\n"
#   "# frozen_string_literal: true\n"
#
# == More Methods
#
# Here is a sampling of other available methods:
#
#   p1 = Pathname.new('/usr/lib')  # => #<Pathname:/usr/lib>
#   p1.absolute?                   # => true
#   p2 = p1 + 'ruby/4.0'           # => #<Pathname:/usr/lib/ruby/4.0>
#   p3 = p1.parent                 # => #<Pathname:/usr>
#   p4 = p2.relative_path_from(p3) # => #<Pathname:lib/ruby/4.0>
#   p4.absolute?                   # => false
#   p5 = Pathname.new('.')         # => #<Pathname:.>
#   p6 = p5 + 'usr/../var'         # => #<Pathname:usr/../var>
#   p6.cleanpath                   # => #<Pathname:var>
#   p6.realpath                    # => #<Pathname:/var>
#   p6.children.take(2)
#   # => [#<Pathname:usr/../var/local>, #<Pathname:usr/../var/spool>]
#
# == Breakdown of functionality
#
# === Core methods
#
# These methods are effectively manipulating a String, because that's
# all a path is.  None of these access the file system except for
# #mountpoint?, #children, #each_child, #realdirpath and #realpath.
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
# - #realdirpath
# - #children
# - #each_child
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
# - #world_readable?
# - #readable_real?
# - #setgid?
# - #setuid?
# - #size
# - #size?
# - #socket?
# - #sticky?
# - #symlink?
# - #writable?
# - #world_writable?
# - #writable_real?
# - #zero?
#
# === File property and manipulation methods
#
# These methods are a facade for File:
# - #each_line(*args, &block)
# - #read(*args)
# - #binread(*args)
# - #readlines(*args)
# - #sysopen(*args)
# - #write(*args)
# - #binwrite(*args)
# - #atime
# - #birthtime
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
# - #lutime(atime, mtime)
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

  # The version string.
  VERSION = "0.4.0"

  # :stopdoc:

  attr_reader :path
  protected :path

  # :startdoc:

  # call-seq:
  #   Pathname.new(path) -> new_pathname
  #
  # Returns a new \Pathname object based on the given +path+,
  # via <tt>File.path(path).dup</tt>.
  # the +path+ may be a String, a File, a Dir, or another \Pathname;
  # see File.path:
  #
  #   Pathname.new('.')               # => #<Pathname:.>
  #   Pathname.new('/usr/bin')        # => #<Pathname:/usr/bin>
  #   Pathname.new(File.new('LEGAL')) # => #<Pathname:LEGAL>
  #   Pathname.new(Dir.new('.'))      # => #<Pathname:.>
  #   Pathname.new(Pathname.new('.')) # => #<Pathname:.>
  #
  def initialize(path)
    @path = File.path(path).dup
  rescue TypeError => e
    raise e.class, "Pathname.new requires a String, #to_path or #to_str", cause: nil
  end

  #  call-seq:
  #    pathname.freeze -> self
  #
  #  Freezes +self+, preventing further modifications;
  #  see {Frozen Objects}[rdoc-ref:frozen_objects.md].
  def freeze
    super
    @path.freeze
    self
  end

  # call-seq:
  #   self == other -> true or false
  #
  # Returns whether the stored paths in +self+ and +other+ are equal:
  #
  #   pn = Pathname('lib')
  #   pn == Pathname('lib')   # => true
  #   pn == Pathname('./lib') # => false
  #
  # Returns +false+ if +other+ is not a pathname:
  #
  #   pn == 'lib'             # => false
  #
  def ==(other)
    return false unless Pathname === other
    other.path == @path
  end
  alias === ==
  alias eql? ==

  def hash # :nodoc:
    @path.hash
  end

  # Return the path as a String.
  def to_s
    @path.dup
  end

  # to_path is implemented so Pathname objects are usable with File.open, etc.
  alias to_path to_s

  def inspect # :nodoc:
    "#<#{self.class}:#{@path}>"
  end

  # :markup: markdown
  #
  # call-seq:
  #   mkpath(permissions = 0775) -> self
  #
  # Creates a directory at the path in `self`;
  # creates intermediate directories as needed:
  #
  # ```ruby
  # pn = Pathname('foo/bar/baz')
  # pn.directory? # => false
  # pn.mkpath     # Creates directories 'foo', 'foo/bar', 'foo/bar/baz'.
  # pn.directory? # => true
  # pn.rmtree     # Clean up.
  # ```
  #
  # Directories are created with the given permissions;
  # see {File Permissions}[rdoc-ref:File@File+Permissions].
  # The permissions for already-existing directories are not changed.
  def mkpath(mode: nil)
    path = @path == '/' ? @path : @path.chomp('/')

    stack = []
    until File.directory?(path) || (parent = File.dirname(path)) == path
      stack.push path
      path = parent
    end

    stack.reverse_each do |dir|
      dir = dir == '/' ? dir : dir.chomp('/')
      if mode
        Dir.mkdir dir, mode
        File.chmod mode, dir
      else
        Dir.mkdir dir
      end
    rescue SystemCallError
      raise unless File.directory?(dir)
    end

    self
  end

  def prepend_prefix(prefix, relpath) # :nodoc:
    if relpath.empty?
      File.dirname(prefix)
    elsif has_separator?(prefix)
      add_trailing_separator(File.dirname(prefix)) + relpath
    else
      prefix + relpath
    end
  end
  private :prepend_prefix

  # :markup: markdown
  #
  # call-seq:
  #   cleanpath(symlinks = false) -> new_pathname
  #
  # Returns a new \Pathname object, "cleaned" of unnecessary separators,
  # single-dot entries, and double-dot entries.
  #
  # When `self` is empty, returns a pathname with a single-dot entry:
  #
  # ```
  # Pathname('').cleanpath # => #<Pathname:.>
  # ```
  #
  # <b>Separators</b>
  #
  # A lone separator is preserved:
  #
  # ```
  # Pathname('/').cleanpath # => #<Pathname:/>
  # ```
  #
  # Multiple trailing separators are removed:
  #
  # ```
  # Pathname('foo/////').cleanpath # => #<Pathname:foo>
  # Pathname('foo/').cleanpath     # => #<Pathname:foo>
  # ```
  #
  # Multiple embedded separators are reduced to a single separator:
  #
  # ```
  # Pathname('foo///bar').cleanpath # => #<Pathname:foo/bar>
  # ```
  #
  # Multiple leading separators are reduced:
  #
  # ```
  # # On Windows, where File.dirname('//') == '//'.
  # Pathname('/////foo').cleanpath # => #<Pathname://foo>
  # Pathname('/////').cleanpath    # => #<Pathname://>
  # # Otherwise, where File.dirname('//') == '/'.
  # Pathname('/////foo').cleanpath # => #<Pathname:/foo>
  # Pathname('/////').cleanpath    # => #<Pathname:/>
  # ```
  #
  # <b>Single-Dot Entries</b>
  #
  # A lone single-dot entry is preserved:
  #
  # ```
  # Pathname('.').cleanpath  # => #<Pathname:.>
  # ```
  #
  # A non-lone single-dot entry, regardless of its location, is removed:
  #
  # ```
  # Pathname('foo/././././bar').cleanpath  # => #<Pathname:foo/bar>
  # Pathname('./foo/./././bar').cleanpath  # => #<Pathname:foo/bar>
  # Pathname('foo/./././bar/./').cleanpath # => #<Pathname:foo/bar>
  # ```
  #
  # <b>Double-Dot Entries</b>
  #
  # A lone double-dot entry is preserved:
  #
  # ```
  # Pathname('..').cleanpath # => #<Pathname:..>
  # ```
  #
  # When a non-lone double-dot entry is preceded by a named entry, both are removed:
  #
  # ```
  # Pathname('foo/..').cleanpath          # => #<Pathname:.>
  # Pathname('foo/../bar').cleanpath      # => #<Pathname:bar>
  # Pathname('foo/../bar/..').cleanpath   # => #<Pathname:.>
  # Pathname('foo/bar/./../..').cleanpath # => #<Pathname:.>
  # ```
  #
  # When a non-lone double-dot entry is _not_ preceded by a named entry,
  # it is preserved:
  #
  # ```
  # Pathname('../..').cleanpath # => #<Pathname:../..>
  # ```
  #
  # A non-lone meaningless double-dot entry is removed:
  #
  # ```
  # Pathname('/..').cleanpath    # => #<Pathname:/>
  # Pathname('/../..').cleanpath # => #<Pathname:/>
  # ```
  #
  # <b> Symbolic Links</b>
  #
  # If the path may contain [symbolic links][symbolic link],
  # consider give optional argument `symlinks` as `true`;
  # the method then uses a more conservative algorithm
  # that avoids breaking symbolic links.
  # This may preserve more double-dot entries than are absolutely necessary,
  # but without accessing the filesystem, this can't be avoided.
  #
  # Examples:
  #
  # ```
  # Pathname('a/').cleanpath           # => #<Pathname:a>
  # Pathname('a/').cleanpath(true)     # => #<Pathname:a/>
  #
  # Pathname('a/.').cleanpath          # => #<Pathname:a>
  # Pathname('a/.').cleanpath(true)    # => #<Pathname:a/.>
  #
  # Pathname('a/./').cleanpath         # => #<Pathname:a>
  # Pathname('a/./').cleanpath(true)   # => #<Pathname:a/.>
  #
  # Pathname('a/b/.').cleanpath        # => #<Pathname:a/b>
  # Pathname('a/b/.').cleanpath(true)  # => #<Pathname:a/b/.>
  #
  # Pathname('a/../.').cleanpath       # => #<Pathname:.>
  # Pathname('a/../.').cleanpath(true) # => #<Pathname:a/..>
  #
  # Pathname('a/b/../../../../c/../d').cleanpath
  # # => #<Pathname:../../d>
  # Pathname('a/b/../../../../c/../d').cleanpath(true)
  # # => #<Pathname:a/b/../../../../c/../d>
  # ```
  #
  # [symbolic link]: https://en.wikipedia.org/wiki/Symbolic_link
  #
  def cleanpath(consider_symlink=false)
    if consider_symlink
      cleanpath_conservative
    else
      cleanpath_aggressive
    end
  end

  #
  # Clean the path simply by resolving and removing excess +.+ and +..+ entries.
  # Nothing more, nothing less.
  #
  def cleanpath_aggressive # :nodoc:
    path = @path
    names = []
    pre = path
    while r = chop_basename(pre)
      pre, base = r
      case base
      when '.'
      when '..'
        names.unshift base
      else
        if names[0] == '..'
          names.shift
        else
          names.unshift base
        end
      end
    end
    pre.tr!(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
    if has_separator?(File.basename(pre))
      names.shift while names[0] == '..'
    end
    self.class.new(prepend_prefix(pre, File.join(*names)))
  end
  private :cleanpath_aggressive

  def cleanpath_conservative # :nodoc:
    path = @path
    names = []
    pre = path
    while r = chop_basename(pre)
      pre, base = r
      names.unshift base if base != '.'
    end
    pre.tr!(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
    if has_separator?(File.basename(pre))
      names.shift while names[0] == '..'
    end
    if names.empty?
      self.class.new(File.dirname(pre))
    else
      if names.last != '..' && File.basename(path) == '.'
        names << '.'
      end
      result = prepend_prefix(pre, File.join(*names))
      if /\A(?:\.|\.\.)\z/ !~ names.last && has_trailing_separator?(path)
        self.class.new(add_trailing_separator(result))
      else
        self.class.new(result)
      end
    end
  end
  private :cleanpath_conservative

  # :markup: markdown
  #
  # call-seq:
  #   parent -> new_pathname
  #
  # Returns a new pathname representing the parent directory
  # of the entry represented by `self`:
  #
  # ```ruby
  # pn = Pathname('/etc/passwd') # => #<Pathname:/etc/passwd>
  # pn.parent                    # => #<Pathname:/etc>
  # ```
  #
  def parent
    self + '..'
  end

  # :markup: markdown
  #
  # call-seq:
  #   mountpoint? -> true or false
  #
  # Returns whether the path in `self` points to a mountpoint:
  #
  # ```ruby
  # Pathname('/').mountpoint?      # => true
  # Pathname('/etc').mountpoint?   # => false
  # Pathname('nosuch').mountpoint? # => false
  # ```
  #
  def mountpoint?
    begin
      stat1 = self.lstat
      stat2 = self.parent.lstat
      stat1.dev != stat2.dev || stat1.ino == stat2.ino
    rescue Errno::ENOENT
      false
    end
  end

  # The opposite of Pathname#absolute?
  #
  # It returns +false+ if the pathname begins with a slash.
  #
  #   p = Pathname.new('/im/sure')
  #   p.relative?
  #       #=> false
  #
  #   p = Pathname.new('not/so/sure')
  #   p.relative?
  #       #=> true
  def relative?
    !absolute?
  end

  # :markup: markdown
  #
  # call-seq:
  #   each_filename {|component| ... } -> nil
  #   each_filename -> new_enumerator
  #
  # With a block given, yields each component of the string path:
  #
  # ```ruby
  # Pathname('/foo/bar/baz').each_filename {|filename| p filename }
  # => nil
  # ```
  #
  # Output:
  #
  # ```text
  # "foo"
  # "bar"
  # "baz"
  # ```
  #
  # With no block given, returns a new Enumerator.
  def each_filename # :yield: filename
    return to_enum(__method__) unless block_given?
    _, names = split_names(@path)
    names.each {|filename| yield filename }
    nil
  end

  # :markup: markdown
  #
  # call-seq:
  #   descend {|entry| ... } -> nil
  #   descend -> new_enumerator
  #
  # With a block given, yields a new pathname for each successive dirname
  # in the stored path; see File.dirname:
  #
  # ```ruby
  # # Absolute path.
  # Pathname('/path/to/some/file.rb').descend {|pn| p pn }
  # # #<Pathname:/>
  # # #<Pathname:/path>
  # # #<Pathname:/path/to>
  # # #<Pathname:/path/to/some>
  # # #<Pathname:/path/to/some/file.rb>
  # # Relative path.
  # Pathname('path/to/some/file.rb').descend {|pn| p pn }
  # # #<Pathname:path>
  # # #<Pathname:path/to>
  # # #<Pathname:path/to/some>
  # # #<Pathname:path/to/some/file.rb>
  # ```
  #
  # With no block given, returns a new Enumerator.
  def descend
    return to_enum(__method__) unless block_given?
    vs = []
    ascend {|v| vs << v }
    vs.reverse_each {|v| yield v }
    nil
  end

  # call-seq:
  #   ascend {|entry| ... } -> nil
  #   ascend -> new_enumerator
  #
  # With a block given,
  # yields +self+, then a new pathname for each successive dirname in the stored path;
  # see File.dirname:
  #
  #   Pathname('/path/to/some/file.rb').ascend {|dirname| p dirname}
  #   #<Pathname:/path/to/some/file.rb>
  #   #<Pathname:/path/to/some>
  #   #<Pathname:/path/to>
  #   #<Pathname:/path>
  #   #<Pathname:/>
  #
  # With no block given, returns a new Enumerator.
  def ascend
    return to_enum(__method__) unless block_given?
    path = @path
    yield self
    while r = chop_basename(path)
      path, = r
      break if path.empty?
      yield self.class.new(del_trailing_separator(path))
    end
  end

  # call-seq:
  #   self + other -> new_pathname
  #
  # Returns a new \Pathname object based on the content of +self+ and +other+;
  # argument +other+ may be a String, a File, a Dir, or another \Pathname:
  #
  #   pn = Pathname('foo')     # => #<Pathname:foo>
  #   pn + 'bar'               # => #<Pathname:foo/bar>
  #   pn + File.new('LEGAL')   # => #<Pathname:foo/LEGAL>
  #   pn + Dir.new('lib')      # => #<Pathname:foo/lib>
  #   pn + Pathname('bar')     # => #<Pathname:foo/bar>
  #
  # When +other+ specifies a relative path (see #relative?),
  # it is combined with +self+ to form a new pathname:
  #
  #   Pathname('/a/b') + 'c' # => #<Pathname:/a/b/c>
  #
  # Extra component separators (<tt>'/'</tt>) are removed:
  #
  #   Pathname('/a/b/') + 'c' # => #<Pathname:/a/b/c>
  #
  # Extra current-directory components (<tt>'.'</tt>) are removed:
  #
  #   Pathname('a') + '.' # => #<Pathname:a>
  #   Pathname('.') + 'a' # => #<Pathname:a>
  #   Pathname('.') + '.' # => #<Pathname:.>
  #
  # Parent-directory components (<tt>'..'</tt>) are:
  #
  # - Resolved, when possible:
  #
  #     Pathname('a')      + '..'      # => #<Pathname:.>
  #     Pathname('a/b')    + '..'      # => #<Pathname:a>
  #     Pathname('/')      + '../a'    # => #<Pathname:/a>
  #     Pathname('a')      + '../b'    # => #<Pathname:b>
  #     Pathname('a/b')    + '../c'    # => #<Pathname:a/c>
  #     Pathname('a//b/c') + '../d//e' # => #<Pathname:a//b/d//e>
  #
  # - Removed, when not needed:
  #
  #     Pathname('/') + '..' # => #<Pathname:/>
  #
  # - Retained, when needed:
  #
  #     Pathname('..') + '..'   # => #<Pathname:../..>
  #     Pathname('..') + '../a' # => #<Pathname:../../a>
  #
  # When +other+ specifies an absolute path (see #absolute?),
  # equivalent to <tt>Pathname(other.to_s)</tt>:
  #
  #   Pathname('/a') + '/b/c' # => #<Pathname:/b/c>
  #
  # Occurrences of <tt>'/'</tt>, <tt>'.'</tt>, and <tt>'..'</tt> are preserved:
  #
  #   Pathname('/a') + '//b//c/./../d' # => #<Pathname://b//c/./../d>
  #
  # This method does not access the file system, so +other+ need not represent
  # an existing (or even a valid) file or directory path:
  #
  #   Pathname('/var') + 'nosuch:ever' # => #<Pathname:/var/nosuch:ever>
  #
  def +(other)
    other = Pathname.new(other) unless Pathname === other
    Pathname.new(plus(@path, other.path))
  end
  alias / +

  # (path1, path2) -> path
  def plus(path1, path2) # :nodoc:
    prefix2 = path2
    index_list2 = []
    basename_list2 = []
    while r2 = chop_basename(prefix2)
      prefix2, basename2 = r2
      index_list2.unshift prefix2.length
      basename_list2.unshift basename2
    end
    return path2 if prefix2 != ''
    prefix1 = path1
    while true
      while !basename_list2.empty? && basename_list2.first == '.'
        index_list2.shift
        basename_list2.shift
      end
      break unless r1 = chop_basename(prefix1)
      prefix1, basename1 = r1
      next if basename1 == '.'
      if basename1 == '..' || basename_list2.empty? || basename_list2.first != '..'
        prefix1 = prefix1 + basename1
        break
      end
      index_list2.shift
      basename_list2.shift
    end
    r1 = chop_basename(prefix1)
    if !r1 && (r1 = has_separator?(File.basename(prefix1)))
      while !basename_list2.empty? && basename_list2.first == '..'
        index_list2.shift
        basename_list2.shift
      end
    end
    if !basename_list2.empty?
      suffix2 = path2[index_list2.first..-1]
      r1 ? File.join(prefix1, suffix2) : prefix1 + suffix2
    else
      r1 ? prefix1 : File.dirname(prefix1)
    end
  end
  private :plus

  # call-seq:
  #   join(*objects) -> new_pathname
  #
  # Joins the string-converted given +objects+ to the string path in +self+;
  # returns a new pathname containing the joined string:
  #
  #   Pathname('foo').join                  # => #<Pathname:foo>
  #   Pathname('foo').join('bar')           # => #<Pathname:foo/bar>
  #   Pathname('foo').join('bar', 'baz')    # => #<Pathname:foo/bar/baz>
  #   Pathname('foo').join(Pathname('bar')) # => #<Pathname:foo/bar>
  #
  def join(*args)
    return self if args.empty?
    result = args.pop
    result = Pathname.new(result) unless Pathname === result
    return result if result.absolute?
    args.reverse_each {|arg|
      arg = Pathname.new(arg) unless Pathname === arg
      result = arg + result
      return result if result.absolute?
    }
    self + result
  end

  # :markup: markdown
  #
  # call-seq:
  #   children(with_dirnames = true) -> array_of_pathnames
  #
  # Returns an array of pathnames;
  # each represents a child of the entry represented by `self`,
  # which must be an existing directory in the underlying file system.
  #
  # With `with_dirnames` given as `true` (the default),
  # each pathname contains the full entry:
  #
  # ```ruby
  # Pathname('lib').children.size # => 72
  # Pathname('lib').children.take(3)
  # # => [#<Pathname:lib/bundled_gems.rb>, #<Pathname:lib/bundler>, #<Pathname:lib/bundler.rb>]
  # ```
  # With `with_dirnames` given as `false`,
  # each pathname contains only the basename of the entry:
  #
  # ```ruby
  # Pathname('lib').children(false).take(3)
  # # => [#<Pathname:bundled_gems.rb>, #<Pathname:bundler>, #<Pathname:bundler.rb>]
  # ```
  #
  # Note that entries `.` and `..` in directory are not actually children,
  # and so are never included in the result.
  def children(with_directory=true)
    with_directory = false if @path == '.'
    result = Dir.children(@path)
    if with_directory
      result.map! {|e| self.class.new(File.join(@path, e))}
    else
      result.map! {|e| self.class.new(e)}
    end
    result
  end

  # :markup: markdown
  #
  # call-seq:
  #   each_child(with_dirnames = true) {|entry| ... } -> array_of_pathnames
  #   each_child(with_dirnames = true) -> new_enumerator
  #
  # With a block given and `with_dirnames` given as `true` (the default),
  # yields a new pathname for each child
  # of the entry represented by `self`;
  # returns an array of those pathnames:
  #
  # ```ruby
  # Pathname('include').each_child {|child| p child }
  # # #<Pathname:include/ruby>
  # # #<Pathname:include/ruby.h>
  # # => [#<Pathname:include/ruby>, #<Pathname:include/ruby.h>]
  # ```
  #
  # With a block given and `with_dirnames` given as `false`,
  # yields a new pathname for each child
  # of the entry represented by `self` with its dirname omitted;
  # returns an array of those pathnames:
  #
  # ```ruby
  # Pathname('include').each_child(false) {|child| p child }
  # # #<Pathname:ruby>
  # # #<Pathname:ruby.h>
  # # => [#<Pathname:ruby>, #<Pathname:ruby.h>]
  # ```
  #
  # Note that entries `'.'` and `'..'` are not children.
  #
  # With no block given, returns a new Enumerator.
  def each_child(with_directory=true, &b)
    children(with_directory).each(&b)
  end

  #
  # Returns a relative path from the given +base_directory+ to the receiver.
  #
  # If +self+ is absolute, then +base_directory+ must be absolute too.
  #
  # If +self+ is relative, then +base_directory+ must be relative too.
  #
  # This method doesn't access the filesystem.  It assumes no symlinks.
  #
  # ArgumentError is raised when it cannot find a relative path.
  #
  # Note that this method does not handle situations where the case sensitivity
  # of the filesystem in use differs from the operating system default.
  #
  def relative_path_from(base_directory)
    base_directory = Pathname.new(base_directory) unless base_directory.is_a? Pathname
    dest_directory = self.cleanpath.path
    base_directory = base_directory.cleanpath.path
    dest_prefix = dest_directory
    dest_names = []
    while r = chop_basename(dest_prefix)
      dest_prefix, basename = r
      dest_names.unshift basename if basename != '.'
    end
    base_prefix = base_directory
    base_names = []
    while r = chop_basename(base_prefix)
      base_prefix, basename = r
      base_names.unshift basename if basename != '.'
    end
    unless same_paths?(dest_prefix, base_prefix)
      raise ArgumentError, "different prefix: #{dest_prefix.inspect} and #{base_directory.inspect}"
    end
    while !dest_names.empty? &&
          !base_names.empty? &&
          same_paths?(dest_names.first, base_names.first)
      dest_names.shift
      base_names.shift
    end
    if base_names.include? '..'
      raise ArgumentError, "base_directory has ..: #{base_directory.inspect}"
    end
    base_names.fill('..')
    relpath_names = base_names + dest_names
    if relpath_names.empty?
      Pathname.new('.')
    else
      Pathname.new(File.join(*relpath_names))
    end
  end
end

class Pathname    # * File *

  # :markup: markdown
  #
  # call-seq:
  #   each_line(sep = $/, **opts) {|line| ... } → nil
  #   each_line(limit, **opts) {|line| ... } → nil
  #   each_line(sep, limit, **opts) {|line| ... } → nil
  #   each_line(...) → new_enumerator
  #
  # With a block given, calls the block with each line
  # from the file represented by `self`;
  # returns `nil`:
  #
  # ```ruby
  # lines = []
  # Pathname('COPYING').each_line {|line| lines << line }
  # lines.take(3)
  # # =>
  # # ["{日本語}[rdoc-ref:COPYING.ja]\n",
  # #  "\n",
  # #  "Ruby is copyrighted free software by Yukihiro Matsumoto <matz@netlab.jp>.\n"]
  # ```
  #
  # The lines are read using IO.foreach,
  # all arguments and options are passed to that method;
  # see details at IO.foreach.
  #
  # With no block given, returns a new Enumerator.
  def each_line(...) # :yield: line
    File.foreach(@path, ...)
  end

  # call-seq:
  #   read(length = nil, offset = 0, **opts) -> string or nil
  #
  # Reads and returns some or all of the content of the file
  # whose path is <tt>self.to_s</tt>.
  #
  # With no arguments given,
  # reads in text mode and returns the entire content of the file:
  #
  #   Pathname.new('t.txt').read
  #   # => "First line\nSecond line\n\nFourth line\nFifth line\n"
  #   Pathname.new('t.ja').read
  #   # => "こんにちは"
  #   Pathname.new('t.dat').read
  #   # => "\xFE\xFF\x99\x90\x99\x91\x99\x92\x99\x93\x99\x94"
  #
  # On Windows, text mode can terminate reading and leave bytes in the file unread
  # when encountering certain special bytes.
  # Consider using #binread if all bytes in the file should be read.
  #
  # With argument +length+ given, returns +length+ bytes if available:
  #
  #   Pathname.new('t.txt').read(7)
  #   # => "First l"
  #   Pathname.new('t.ja').read(7)
  #   # => "\xE3\x81\x93\xE3\x82\x93\xE3"
  #   Pathname.new('t.dat').read(7)
  #   # => "\xFE\xFF\x99\x90\x99\x91\x99"
  #
  # Returns all bytes if +length+ is larger than the files size:
  #
  #   Pathname.new('t.txt').read(700)
  #   # => "First line\r\nSecond line\r\n\r\nFourth line\r\nFifth line\r\n"
  #   Pathname.new('t.ja').read(700)
  #   # => "\xE3\x81\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1\xE3\x81\xAF"
  #   Pathname.new('t.dat').read(700)
  #   # => "\xFE\xFF\x99\x90\x99\x91\x99\x92\x99\x93\x99\x94"
  #
  # With arguments +length+ and +offset+ given,
  # returns +length+ bytes if available, beginning at the given +offset+:
  #
  #   Pathname.new('t.txt').read(10, 2)
  #   # => "rst line\r\n"
  #   Pathname.new('t.ja').read(10, 2)
  #   # => "\x93\xE3\x82\x93\xE3\x81\xAB\xE3\x81\xA1"
  #   Pathname.new('t.dat').read(10, 2)
  #   # => "\x99\x90\x99\x91\x99\x92\x99\x93\x99\x94"
  #
  # Returns +nil+ if +offset+ is past the end of the file:
  #
  #   Pathname.new('t.txt').read(10, 200) # => nil
  #
  # Optional keyword arguments +opts+ specify:
  #
  # - {Open Options}[rdoc-ref:IO@Open+Options].
  # - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
  #
  def read(...) File.read(@path, ...) end

  # call-seq:
  #   binread(length = nil, offset = 0) -> string or nil
  #
  # Behaves like #read, except that the file is opened in binary mode
  # with ASCII-8BIT encoding.
  #
  def binread(...) File.binread(@path, ...) end

  # See <tt>File.readlines</tt>.  Returns all the lines from the file.
  def readlines(...) File.readlines(@path, ...) end

  # See <tt>File.sysopen</tt>.
  def sysopen(...) File.sysopen(@path, ...) end

  # call-seq:
  #   write(data, offset = 0, **opts) -> nonnegative_integer
  #
  # Opens the file at +self.to_s+, writes the given +data+ to it,
  # and closes the file; returns the number of bytes written.
  #
  # With only argument +data+ given, writes the given data to the file:
  #
  #   path = 't.tmp'
  #   pn = Pathname.new(path)
  #   pn.write('foo') # => 3
  #   File.read(path) # => "foo"
  #
  # If +offset+ is zero (the default), the file is overwritten:
  #
  #   pn.write('bar')
  #   File.read(path) # => "bar"
  #
  # If +offset+ in within the file content, the file is partly overwritten:
  #
  #   pn.write('foobarbaz')
  #   pn.write('BAR', 3)
  #   File.read(path) # => "fooBARbaz"
  #
  # If +offset+ is outside the file content,
  # the file is padded with null characters <tt>"\u0000"</tt>:
  #
  #   pn.write('bat', 12)
  #   File.read(path) # => "fooBARbaz\u0000\u0000\u0000bat"
  #
  # Optional keyword arguments +opts+ specify:
  #
  # - {Open Options}[rdoc-ref:IO@Open+Options].
  # - {Encoding options}[rdoc-ref:encodings.rdoc@Encoding+Options].
  #
  def write(...) File.write(@path, ...) end

  # call-seq:
  #   binwrite(string, offset = 0, **opts) -> nonnegative_integer
  #
  # Behaves like #write, except that the file is opened in binary mode
  # with ASCII-8BIT encoding.
  def binwrite(...) File.binwrite(@path, ...) end

  # :markup: markdown
  #
  # call-seq:
  #   atime -> new_time
  #
  # Returns a Time object containing the access time
  # of the entry represented by `self`, as reported by the filesystem;
  # see {File System Access Time}[rdoc-ref:file/timestamps.md@Access+Time]:
  #
  # ```ruby
  # # Pathname for a (non-existent) directory.
  # dir_pn = Pathname('doc/foo')   # => #<Pathname:doc/foo>
  # # Create directory; establishes atime for directory.
  # dir_pn.mkdir
  # dir_pn.atime                   # => 2026-06-17 10:10:20.801115774 -0500
  # # Pathname for a (non-existent) file in the directory.
  # file_pn = dir_pn.join('t.tmp') # => #<Pathname:doc/foo/t.tmp>
  # # Create file; establishes atime for file, updates atime for directory.
  # file_pn.write('foo')
  # file_pn.atime                  # => 2026-06-17 10:11:40.987171568 -0500
  # dir_pn.atime                   # => 2026-06-17 10:11:40.96617277 -0500
  # # Write file; updates atime for file,but not directory.
  # file_pn.write('bar')
  # file_pn.atime                  # => 2026-06-17 10:13:22.062904563 -0500
  # dir_pn.atime                   # => 2026-06-17 10:11:40.96617277 -0500
  # # Read file; may update atime for file, but not directory.
  # file_pn.read
  # file_pn.atime                  # => 2026-06-17 10:13:22.062904563 -0500
  # dir_pn.atime                   # => 2026-06-17 10:11:40.96617277 -0500
  # # Clean up.
  # file_pn.delete
  # dir_pn.rmdir
  # ```
  #
  def atime() File.atime(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   birthtime -> new_time
  #
  # Returns a new Time object containing the create time of the entry
  # represented by `self`;
  # see [File System Timestamps](rdoc-ref:file/timestamps.md):
  #
  # ```ruby
  # # A directory and its Pathname.
  # dir_path = 'doc/foo'
  # dir_pn = Pathname(dir_path)
  # # Create directory; directory birthtime established.
  # dir_pn.mkdir
  # dir_pn.birthtime  # => 2026-06-16 17:06:10.779192552 -0500
  # # A file therein and its Pathname.
  # file_path = dir_pn.join('t.tmp')
  # file_pn = Pathname(file_path)
  # # Create file; file birthtime established; directory birthtime not updated.
  # file_pn.write('foo')
  # dir_pn.birthtime  # => 2026-06-16 17:06:10.779192552 -0500
  # file_pn.birthtime # => 2026-06-16 17:07:59.339330622 -0500
  # # Modify file; neither birthtime updated.
  # file_pn.write('bar')
  # dir_pn.birthtime  # => 2026-06-16 17:06:10.779192552 -0500
  # file_pn.birthtime # => 2026-06-16 17:07:59.339330622 -0500
  # # Clean up.
  # dir_pn.rmtree
  # ```
  #
  def birthtime() File.birthtime(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   ctime -> new_time
  #
  # On Windows, returns the #birthtime.
  #
  # On other systems,
  # returns a new Time object containing the time of the most recent
  # metadata change to the entry represented by `self`;
  # see {File System Timestamps}[rdoc-ref:file/timestamps.md]:
  #
  # ```ruby
  # # A directory and its Pathname.
  # dir_path = 'doc/foo'
  # dir_pn = Pathname(dir_path)
  # # Create directory; directory ctime established.
  # dir_pn.mkdir
  # dir_pn.ctime  # => 2026-06-16 16:44:15.86720572 -0500
  # # A file therein and its Pathname.
  # file_path = dir_pn.join('t.tmp')
  # file_pn = Pathname(file_path)
  # # Create file; file ctime established; directory ctime updated.
  # file_pn.write('foo')
  # file_pn.ctime # => 2026-06-16 16:46:00.734974872 -0500
  # dir_pn.ctime  # => 2026-06-16 16:46:00.734974872 -0500
  # # Write file; file ctime updated; directory ctime not updated.
  # file_pn.write('bar')
  # file_pn.ctime # => 2026-06-16 16:49:11.421204188 -0500
  # dir_pn.ctime  # => 2026-06-16 16:46:00.734974872 -0500
  # # Read file; neither ctime updated.
  # file_pn.read
  # file_pn.ctime # => 2026-06-16 16:49:11.421204188 -0500
  # dir_pn.ctime  # => 2026-06-16 16:46:00.734974872 -0500
  # # Clean up.
  # dir_pn.rmtree
  # ```
  #
  def ctime() File.ctime(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   mtime -> time
  #
  # Returns a Time object containing the time of the most recent
  # modification to the entry represented by `self`;
  # see {File System Timestamps}[rdoc-ref:file/timestamps.md]:
  #
  # ```ruby
  # # A directory and its Pathname.
  # dir_path = 'doc/foo'
  # dir_pn = Pathname(dir_path)
  # # Create directory; directory mtime established.
  # dir_pn.mkdir
  # dir_pn.mtime  # => 2026-06-28 16:38:02.675780521 -0500
  # # A file therein and its Pathname.
  # file_path = dir_pn.join('t.tmp')
  # file_pn = Pathname(file_path)
  # # Create file; file mtime established; directory mtime updated.
  # file_pn.write('foo')
  # dir_pn.mtime  # => 2026-06-28 16:41:23.107750483 -0500
  # file_pn.mtime # => 2026-06-28 16:41:23.107750483 -0500
  # # Modify file; file mtime updated; directory mtime unchanged.
  # file_pn.write('bar')
  # dir_pn.mtime  # => 2026-06-28 16:41:23.107750483 -0500
  # file_pn.mtime # => 2026-06-28 16:42:48.869163049 -0500
  # # Clean up.
  # dir_pn.rmtree
  # ```
  #
  def mtime() File.mtime(@path) end


  # :markup: markdown
  #
  # call-seq:
  #   chmod(mode) -> 1
  #
  # Changes the mode (i.e., permissions) of the entry represented by `self`;
  # see {File Permissions}[rdoc-ref:File@File+Permissions]:
  #
  # ```ruby
  # # Pathname for a (non-existent) directory.
  # dir_pn = Pathname('doc/foo') # => #<Pathname:doc/foo>
  # # Create the directory and fetch its mode.
  # dir_pn.mkdir
  # dir_pn.stat.mode.to_s(8) # => "40775"
  # # Change the directory mode and fetch the new mode.
  # dir_pn.chmod(0777)
  # dir_pn.stat.mode.to_s(8) # => "40777"
  #
  # # Pathname for a (non-existent) file in the directory.
  # file_pn = dir_pn.join('t.tmp') # => #<Pathname:doc/foo/t.tmp>
  # # Create the file and fetch its mode.
  # file_pn.write('foo')
  # file_pn.stat.mode.to_s(8) # => "100664"
  # # Change the file mode and fetch its new mode.
  # file_pn.chmod(0777)
  # file_pn.stat.mode.to_s(8) # => "100777"
  #
  # # Clean up.
  # file_pn.delete
  # dir_pn.rmdir
  # ```
  #
  def chmod(mode) File.chmod(mode, @path) end

  #  :markup: markdown
  #
  #  call-seq:
  #    Pathname.lchmod(mode) -> 1
  #
  #  Not supported on some platforms (raises Errno:: ENOTSUP).
  #
  #  When supported: like Pathname::chmod, but does not follow symbolic links,
  #  and therefore changes the mode of the entry specified by `self`:
  #
  #  ```ruby
  #  File.write('t.tmp', '')
  #  File.symlink('t.tmp', 'link')
  #  File.stat('t.tmp').mode.to_s(8) # => "100664"
  #  File.stat('link').mode.to_s(8)  # => "100664"
  #  Pathname('link').lchmod(0777)
  #  File.stat('t.tmp').mode.to_s(8) # => "100664"
  #  File.stat('link').mode.to_s(8)  # => "100777"
  #  File.delete('t.tmp')
  #  File.delete('link')
  #  ```
  #
  def lchmod(mode) File.lchmod(mode, @path) end

  # :markup: markdown
  #
  # call-seq:
  #   chown(owner_id, group_id) -> 0
  #
  # Changes the owner and group of an entry (directory or file):
  #
  # ```ruby
  # # Super user; all privileges.
  # Process.uid                    # => 0
  # Process.gid                    # => 0
  #
  # # Pathname for a (non-existent) directory.
  # dir_pn = Pathname('doc/foo')   # => #<Pathname:doc/foo>
  # # Create the directory; fetch original owner and group.
  # dir_pn.mkdir
  # dir_stat = dir_pn.stat
  # dir_stat.uid                   # => 0
  # dir_stat.gid                   # => 0
  # # Change owner; fetch current owner and group.
  # dir_pn.chown(1000, 1000)
  # dir_stat = dir_pn.stat
  # dir_stat.uid                   # => 1000
  # dir_stat.gid                   # => 1000
  #
  # Pathname for a (non-existent) file in the directory.
  # file_pn = dir_pn.join('t.tmp') # => #<Pathname:doc/foo/t.tmp>
  # # Create the directory; fetch original owner and group.
  # file_pn.write('foo')
  # file_stat = file_pn.stat
  # file_stat.uid                  # => 0
  # file_stat.gid                  # => 0
  # # Change owner; fetch current owner and group.
  # file_pn.chown(1000, 1000)
  # file_stat = file_pn.stat
  # file_stat.uid                  # => 1000
  # file_stat.gid                  # => 1000
  # # Clean up.
  # file_pn.delete
  # dir_pn.rmdir
  # ```
  #
  # Notes:
  #
  # - On Windows, the owner and group are not changed.
  # - Only a process with superuser privileges can change the owner of an entry.
  # - The owner of an entry can change its group to any group
  #   to which the owner belongs.
  # - A +nil+ or +-1+ owner or group id is ignored.
  # - The method follows symbolic links to the target entry.
  #
  def chown(owner, group) File.chown(owner, group, @path) end

  # :markup: markdown
  #
  # call-seq:
  #   lchown(uid, gid) -> 1
  #
  #  Not supported on some platforms (raises exception).
  #
  #  Calling process must have superuser privileges.
  #
  #  When supported: like Pathname#chown, but does not follow symbolic links,
  #  and therefore changes the ownership of the entry at the path in `self`:
  #
  # ```ruby
  # # Super user; all privileges.
  # Process.uid # => 0
  # Process.gid # => 0
  # # Create regular file and symbolic link to it.
  # File.write('t.tmp', '')
  # File.symlink('t.tmp', 'link')
  # # Capture original statuses.
  # fstat0 = File.stat('t.tmp')  # Method ::stat; status of file.
  # lstat0 = File.lstat('link')  # Method ::lstat; status of link.
  # # Original user ids and group ids.
  # fstat0.uid # => 0
  # fstat0.gid # => 0
  # lstat0.uid # => 0
  # lstat0.gid # => 0
  # # Change ids for link.
  # Pathname('link').lchown(1000, 1000)
  # # Capture new statuses.
  # fstat1 = File.stat('t.tmp')
  # lstat1 = File.lstat('link')
  # # User id and group id for file not changed.
  # fstat1.uid # => 0
  # fstat1.gid # => 0
  # # User id and group id for link changed.
  # p lstat1.uid # => 1000
  # p lstat1.gid # => 1000
  # # Clean up.
  # File.delete('t.tmp')
  # File.delete('link')
  # ```
  #
  def lchown(owner, group) File.lchown(owner, group, @path) end

  # :markup: markdown
  #
  # call-seq:
  #   File.fnmatch(pattern, flags = 0) -> true or false
  #
  # Returns whether string `pattern` matches against the string path in `self`,
  # under the control of the given `flags`;
  # see [Filename Matching](rdoc-ref:file/filename_matching.md).
  def fnmatch(pattern, ...) File.fnmatch(pattern, @path, ...) end

  # See <tt>File.fnmatch?</tt> (same as #fnmatch).
  def fnmatch?(pattern, ...) File.fnmatch?(pattern, @path, ...) end

  #  call-seq:
  #    pathname.ftype -> string
  #
  #  Returns the string type of the object at the path in +self+:
  #
  #    Pathname('README.md').ftype   # => "file"
  #    Pathname('lib').ftype         # => "directory"
  #    Pathname('/dev/null').ftype   # => "characterSpecial"
  #    Pathname('/dev/loop0').ftype  # => "blockSpecial"
  #
  #    File.mkfifo('/tmp/pipe', 0666)
  #    Pathname('/tmp/pipe').ftype   # => "fifo"
  #
  #    File.symlink('lib', 'lib_link')
  #    Pathname('lib_link').ftype    # => "link"
  #
  #    require 'socket'
  #    UNIXServer.new('/tmp/socket')
  #    Pathname('/tmp/socket').ftype # => "socket"
  #
  #  Returns <tt>'unknown'</tt> if the type cannot be determined.
  def ftype() File.ftype(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   make_link(path) -> 0
  #
  #  Not available on some systems.
  #
  # Creates a new entry at the path in `self` for the existing entry at `path`
  # using a [hard link](https://en.wikipedia.org/wiki/Hard_link):
  #
  # ```ruby
  # File.write('doc/t.tmp', 'foo')
  # Pathname('lib/u.tmp').make_link('doc/t.tmp')
  # File.read('lib/u.tmp') # => "foo"
  # File.write('lib/u.tmp', 'bar')
  # File.read('doc/t.tmp') # => "bar"
  # File.delete('doc/t.tmp')
  # File.read('lib/u.tmp') # => "bar"
  # File.delete('lib/u.tmp')
  # ```
  #
  # Raises an exception if the entry at the path in `self` exists.
  def make_link(old) File.link(old, @path) end

  # See <tt>File.open</tt>.  Opens the file for reading or writing.
  def open(...) # :yield: file
    File.open(@path, ...)
  end

  # :markup: markdown
  #
  # call-seq:
  #   readlink -> new_pathname
  #
  # Returns a new pathname containing the string path to the entry referenced by `self`:
  #
  # ```ruby
  # # Create Pathnames.
  # file_pn = Pathname('doc/extension.rdoc') # => #<Pathname:doc/extension.rdoc>
  # target_pn = Pathname('..').join(file_pn) # => #<Pathname:../doc/extension.rdoc>
  # link_pn = Pathname('lib/u.tmp')          # => #<Pathname:lib/u.tmp>
  # link_pn.make_symlink(target_pn)
  # link_pn.readlink                         # => #<Pathname:../doc/extension.rdoc>
  # link_pn.delete
  # ```
  #
  def readlink() self.class.new(File.readlink(@path)) end

  # See <tt>File.rename</tt>.  Rename the file.
  def rename(to) File.rename(@path, to) end

  # See <tt>File.stat</tt>.  Returns a <tt>File::Stat</tt> object.
  def stat() File.stat(@path) end

  #
  #  :markup: markdown
  #
  #  call-seq:
  #    lstat -> new_stat
  #
  #  Returns a File::Stat object for the path in `self`;
  #  does not follow symbolic links,
  #  and therefore returns the stat object for that path,
  #  regardless of whether it is a symbolic link:
  #
  #  ```ruby
  #  File.write('t.tmp', '')
  #  sleep(1)
  #  File.symlink('t.tmp', 'link')
  #  pn = Pathname('link')
  #  # => #<Pathname:link>
  #  # Method stat: follows link to 't.tmp'.
  #  pn.stat.ctime  # => 2026-06-13 15:02:46.562620885 -0500
  #  # Method lstat; does not follow link.
  #  pn.lstat.ctime # => 2026-06-13 15:02:47.563619647 -0500
  #  File.delete('t.tmp')
  #  File.delete('link')
  #  ```
  #
  def lstat() File.lstat(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   make_symlink(path) -> 0
  #
  # Creates a symbolic link at the path in `self` to the entry at `path`:
  #
  # ```ruby
  # # Create Pathnames.
  # file_pn = Pathname('doc/extension.rdoc') # => #<Pathname:doc/extension.rdoc>
  # target_pn = Pathname('..').join(file_pn) # => #<Pathname:../doc/extension.rdoc>
  # link_pn = Pathname('lib/u.tmp')          # => #<Pathname:lib/u.tmp>
  # # Create link and verify.
  # link_pn.make_symlink(target_pn)
  # file_pn.read == link_pn.read             # => true
  # link_pn.delete                           # Clean up.
  # ```
  #
  # See also: #read, #readlink, #symlink?.
  def make_symlink(old) File.symlink(old, @path) end

  # See <tt>File.truncate</tt>.  Truncate the file to +length+ bytes.
  def truncate(length) File.truncate(@path, length) end

  # :markup: markdown
  #
  # call-seq:
  #   utime(atime, mtime) -> 1
  #
  # For the entry at the path in `self`,
  # updates its access time to the given `atime`
  # and its modification time to the given `mtime`;
  # each given time may be a Time object, an integer representing a time,
  # or `nil` (meaning Time.now):
  #
  # ```ruby
  # pn = Pathname('doc/t.tmp')
  # pn.write('foo')
  # pn.stat.atime   # => 1969-12-31 18:00:00 -0600
  # pn.stat.mtime   # => 2026-07-11 16:12:15.832556524 -0500
  # pn.utime(0, 0)
  # pn.stat.atime   # => 1969-12-31 18:00:00 -0600
  # pn.stat.mtime   # => 1969-12-31 18:00:00 -0600
  # pn.utime(nil, nil)
  # pn.stat.atime   # => 2026-07-11 16:13:06.982646673 -0500
  # pn.stat.mtime   # => 2026-07-11 16:13:04.983530291 -0500
  # time = Time.now # => 2026-07-11 16:13:40.190110708 -0500
  # pn.utime(time, time)
  # pn.stat.atime   # => 2026-07-11 16:13:51.99317823 -0500
  # pn.stat.mtime   # => 2026-07-11 16:13:40.190110708 -0500
  # ```
  #
  # Follows symbolic links:
  #
  # ```ruby
  # link_pn = Pathname('link')
  # link_pn.make_symlink(pn)
  # link_pn.stat.atime # => 2026-07-11 16:13:51.99317823 -0500
  # link_pn.stat.mtime # => 2026-07-11 16:13:40.190110708 -0500
  # link_pn.utime(0, 0)
  # pn.stat.atime      # => 1969-12-31 18:00:00 -0600
  # pn.stat.mtime      # => 1969-12-31 18:00:00 -0600
  # pn.delete
  # link_pn.delete
  # ```
  def utime(atime, mtime) File.utime(atime, mtime, @path) end

  # :markup: markdown
  #
  # call-seq:
  #   lutime(atime, mtime) -> 1
  #
  # Like Pathname#utime, but does not follow symbolic links,
  # and therefore changes the times of the entry in `self`,
  # regardless of whether it is a symbolic link:
  #
  # ```ruby
  # # Create a file and a link to it.
  # file_path = 't.tmp'
  # link_path = 'link'
  # File.write(file_path, '')
  # File.symlink(file_path, link_path)
  # # Take snapshots of both.
  # file_stat = File.stat(file_path)
  # link_stat = File.lstat(link_path)
  # # Fetch access times and modification times of both.
  # file_stat.atime # => 2026-06-15 11:03:29.600373255 -0500
  # file_stat.mtime # => 2026-06-15 11:03:22.247352211 -0500
  # link_stat.atime # => 2026-06-15 11:03:29.251372254 -0500
  # link_stat.mtime # => 2026-06-15 11:03:26.66436484 -0500
  # # Update access time and modification time of the link.
  # pn = Pathname(link_path)
  # time = Time.now # => 2026-06-15 11:08:07.384287523 -0500
  # pn.lutime(time, time)
  # # Take fresh snapshots of both.
  # file_stat = File.stat(file_path)
  # link_stat = File.lstat(link_path)
  # # Fetch access time and modification time of file (not changed).
  # file_stat.atime # => 2026-06-15 11:03:29.600373255 -0500
  # file_stat.mtime # => 2026-06-15 11:03:22.247352211 -0500
  # # Fetch access time and modification time of link (changed).
  # link_stat.atime # => 2026-06-15 11:08:29.847301399 -0500
  # link_stat.mtime # => 2026-06-15 11:08:07.384287523 -0500
  # # Clean up.
  # File.delete(file_path)
  # File.delete(link_path)
  # ```
  #
  # Arguments `atime` and `mtime` may be Time objects (as above).
  #
  # Either or both may be integers;
  # when an integer `i` is passed, `Time.new(i)` is used.
  #
  # Either or both may be `nil`, in which case `Time.now` is used.
  #
  # See {File System Timestamps}[rdoc-ref:file/timestamps.md].
  #
  def lutime(atime, mtime) File.lutime(atime, mtime, @path) end

  # call-seq:
  #   basename(path, suffix = '') -> new_pathname
  #
  # Returns a new \Pathname object containing all or part of the last entry
  # of the path represented by +self+.
  # Entries are delimited by the value of constant File::SEPARATOR
  # and, if non-nil, the value of constant File::ALT_SEPARATOR.
  #
  # When +suffix+ is the empty string <tt>''</tt>, returns all of the last entry:
  #
  #   Pathname.new('foo/bar/baz/bat.txt').basename # => #<Pathname:bat.txt>
  #   Pathname.new('foo/bar/baz').basename         # => #<Pathname:baz>
  #
  #   File::SEPARATOR                              # => "/"
  #   Pathname.new('foo/bar.txt////').basename     # => #<Pathname:bar.txt>
  #   File::ALT_SEPARATOR # => "\\"                # On Windows.
  #   Pathname.new('foo/bar.txt//\\\\//').basename # => #<Pathname:bar.txt>
  #
  # When +suffix+ is <tt>'.*'</tt>,
  # the last {filename extension}[https://en.wikipedia.org/wiki/Filename_extension],
  # if any, is removed:
  #
  #   Pathname.new('foo/bar.txt').basename('.*')     # => #<Pathname:bar>
  #   Pathname.new('foo/bar.txt.old').basename('.*') # => #<Pathname:bar.txt>
  #   Pathname.new('foo/bar').basename('.*')         # => #<Pathname:bar>
  #
  # When +suffix+ is any string other than <tt>''</tt> or <tt>'.*'</tt>,
  # the matching trailing substring, if any, is removed:
  #
  #   Pathname.new('foo/bar.txt').basename('.txt') # => #<Pathname:bar>
  #   Pathname.new('foo/bar.txt').basename('txt')  # => #<Pathname:bar.>
  #   Pathname.new('foo/bar.txt').basename('*')    # => #<Pathname:bar.txt>
  #   Pathname.new('foo/bar.txt').basename('.')    # => #<Pathname:bar.txt>
  #
  def basename(...) self.class.new(File.basename(@path, ...)) end

  # See <tt>File.dirname</tt>.  Returns all but the last component of the path.
  def dirname() self.class.new(File.dirname(@path)) end

  # :markup: markdown
  #
  # call-seq:
  #   extname -> extension
  #
  # Returns the filename extension of `self` --
  # usually the portion of the string path beginning from the last period:
  #
  # ```ruby
  # Pathname('t.rb').extname               # => ".rb"
  # Pathname('foo.bar.t.rb').extname       # => ".rb"
  # Pathname('foo/bar/t.rb').extname       # => ".rb"
  # Pathname('nosuch.txt').extname         # => ".txt"  # Path need not exist.
  # ```
  #
  # Returns the entire string when there is no period:
  #
  # ```ruby
  # Pathname('foo').extname # => ""
  # ```
  #
  # Returns an empty string when the only period is the first character:
  #
  # ```ruby
  # Pathname('.irbrc').extname # => ""
  # ```
  #
  # Returns an empty string or `'.'` when `path` ends with a period:
  #
  # ```ruby
  # Pathname('foo.').extname    # => ""   # On Windows.
  # Pathname('foo.').extname    # => "."  # Elsewhere.
  # Pathname('foo....').extname # => ""   # On Windows.
  # Pathname('foo....').extname # => "."  # Elsewhere.
  # ```
  #
  def extname() File.extname(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   expand_path(dirpath = '.') -> new_pathname
  #
  # Returns a new pathname containing the absolute path for `self`.
  #
  # Evaluates a relative path with respect to the directory given by `dirpath`:
  #
  # ```ruby
  # Dir.chdir('/snap')
  # # Default dirpath.
  # Pathname('README').expand_path                  # => #<Pathname:/snap/README>
  # Pathname('bin').expand_path                     # => #<Pathname:/snap/bin>
  # Pathname('bin/../var').expand_path              # => #<Pathname:/snap/var>  # Cleaned.
  # # Other dirpath.
  # Pathname('../zip').expand_path('/usr/bin/ruby') # => #<Pathname:/usr/bin/zip>
  # Dir.chdir('/usr/bin')
  # Pathname('../../snap').expand_path(__FILE__)    # => #<Pathname:/usr/snap>
  # ```
  #
  # Evaluates an absolute path without respect to `dirpath`:
  #
  # ```ruby
  # Pathname('/snap').expand_path                       # => #<Pathname:/snap>
  # Pathname('/snap').expand_path.expand_path('nosuch') # => #<Pathname:/snap>
  # Pathname('/snap/../snap').expand_path               # => #<Pathname:/snap>  # Cleaned.
  # ```
  #
  # More examples:
  #
  # ```
  # Dir.chdir('/usr/bin')
  # Pathname('../../snap').expand_path(__FILE__) # => #<Pathname:/usr/snap>
  # Pathname('../../snap').expand_path           # => #<Pathname:/snap>
  # ```
  #
  def expand_path(...) self.class.new(File.expand_path(@path, ...)) end

  # See <tt>File.split</tt>.  Returns the #dirname and the #basename in an
  # Array.
  def split()
    array = File.split(@path)
    raise TypeError, 'wrong argument type nil (expected Array)' unless Array === array
    array.map {|f| self.class.new(f) }
  end

  # Returns the real (absolute) pathname for +self+ in the actual filesystem.
  #
  # Does not contain symlinks or useless dots, +..+ and +.+.
  #
  # All components of the pathname must exist when this method is called.
  def realpath(...) self.class.new(File.realpath(@path, ...)) end

  # Returns the real (absolute) pathname of +self+ in the actual filesystem.
  #
  # Does not contain symlinks or useless dots, +..+ and +.+.
  #
  # The last component of the real pathname can be nonexistent.
  def realdirpath(...) self.class.new(File.realdirpath(@path, ...)) end
end


class Pathname    # * FileTest *

  # :markup: markdown
  #
  # call-seq:
  #   blockdev? => true or false
  #
  # Returns whether `self` represents a path to a block device
  # (i.e., a direct-access device):
  #
  # ```ruby
  # Pathname('/dev/nvme0n1').blockdev? # => true
  # Pathname('/dev/loop0').blockdev?   # => true
  # Pathname('/dev/tty').blockdev?     # => false
  # Pathname('/dev/null').blockdev?    # => false
  # Pathname('nosuch').blockdev?       # => false
  # Pathname($stdin).blockdev?         # => false
  # ```
  #
  # The returned value is OS-dependent; on Windows, almost always `false`.
  def blockdev?() FileTest.blockdev?(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   chardev? => true or false
  #
  # Returns whether `self` represents a path to  a character device
  # (i.e., a sequential-access device):
  #
  # ```ruby
  # Pathname('/dev/tty').chardev?     # => true
  # Pathname('/dev/null').chardev?    # => true
  # Pathname('/dev/nvme0n1').chardev? # => false
  # Pathname('/dev/loop0').chardev?   # => false
  # Pathname($stdin).chardev?         # => false
  # Pathname('nosuch').chardev?       # => false
  # ```
  #
  # The returned value is OS-dependent; on Windows, almost always `false`.
  def chardev?() FileTest.chardev?(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   empty? -> true or false
  #
  # Returns whether the entry represented by `self` exists and is empty:
  #
  # ```ruby
  # dir_pn = Pathname('example_dir')
  # dir_pn.empty?  # => false  # Dir does not exist.
  # dir_pn.mkdir
  # dir_pn.empty?  # => true   # Dir exists and is empty.
  #
  # file_pn = Pathname('example_dir/example.txt')
  # file_pn.empty? # => false  # File does not exist.
  # file_pn.write('')
  # file_pn.empty? # => true   # File exists and is empty.
  # dir_pn.empty?  # => false  # Dir exists and is not empty.
  # file_pn.write('foo')
  # file_pn.empty? # => false  # File exists and is not empty.
  #
  # file_pn.delete
  # dir_pn.delete
  # ```
  #
  def empty?
    if FileTest.directory?(@path)
      Dir.empty?(@path)
    else
      File.empty?(@path)
    end
  end

  # :markup: markdown
  #
  # call-seq:
  #   executable? -> true or false
  #
  # Returns whether the entry represented by `self` is executable;
  # calls FileTest.executable? with argument `self.to_s`:
  #
  # ```ruby
  # Pathname('bin/gem').executable?   # => true
  # Pathname('README.md').executable? # => false
  # ```
  #
  def executable?() FileTest.executable?(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   executable_real? -> true or false
  #
  # Returns whether the entry represented by `self` is executable
  # by the real user and group id of the current process;
  # calls FileTest.executable_real? with argument `self.to_s`:
  #
  # ```ruby
  # pn = Pathname('example')
  # pn.write('')
  # pn.executable_real? # => false
  # pn.chmod(0100)
  # pn.executable_real? # => true
  # ```
  #
  def executable_real?() FileTest.executable_real?(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   exist? -> true or false
  #
  # Returns whether the entry represented by `self` exists:
  #
  # ```ruby
  # Pathname('.').exist?         # => true
  # Pathname('README.md').exist? # => true
  # Pathname('nosuch').exist?    # => false
  # ```
  #
  def exist?() FileTest.exist?(@path) end

  # call-seq:
  #   grpowned?(path) -> true or false
  #
  # Returns whether the filesystem entry for the path stored in +self+ exists,
  # and the effective group id of the calling process is the owner of the entry:
  #
  #   Pathname('README.md').grpowned?   # => true
  #   Pathname('lib').grpowned?         # => true
  #   Pathname('/etc/passwd').grpowned? # => false
  #   Pathname('nosuch').grpowned?      # => false
  #
  # Returns +false+ on Windows.
  def grpowned?() FileTest.grpowned?(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   directory? -> true or false
  #
  # Returns whether the entry represented by `self` is a directory:
  #
  # ```ruby
  # Pathname('/etc').directory?      # => true
  # Pathname('lib').directory?       # => true
  # Pathname('README.md').directory? # => false
  # Pathname('nosuch').directory?    # => false
  # ```
  #
  def directory?() FileTest.directory?(@path) end

  # See <tt>FileTest.file?</tt>.
  def file?() FileTest.file?(@path) end

  # See <tt>FileTest.pipe?</tt>.
  def pipe?() FileTest.pipe?(@path) end

  # See <tt>FileTest.socket?</tt>.
  def socket?() FileTest.socket?(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   owned? -> true or false
  #
  # Returns whether the entry at the path represented by `self`
  # exists and is owned by the user of the current process:
  #
  # ```ruby
  # pn = Pathname('doc/t.tmp')
  # pn.write('foo')
  # pn.owned?               # => true
  # pn.delete
  # pn = Pathname('doc/tmp')
  # pn.mkdir
  # pn.owned?               # => true
  # pn.rmdir
  # Pathname('/etc').owned? # => false
  # ```
  #
  def owned?() FileTest.owned?(@path) end

  # See <tt>FileTest.readable?</tt>.
  def readable?() FileTest.readable?(@path) end

  # See <tt>FileTest.world_readable?</tt>.
  def world_readable?() File.world_readable?(@path) end

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

  # :markup: markdown
  #
  # call-seq:
  #   symlink? -> true or false
  #
  # Returns whether the entry at the path in `self` is a symbolic link:
  #
  # ```ruby
  # # Create Pathnames.
  # file_pn = Pathname('doc/extension.rdoc') # => #<Pathname:doc/extension.rdoc>
  # target_pn = Pathname('..').join(file_pn) # => #<Pathname:../doc/extension.rdoc>
  # link_pn = Pathname('lib/u.tmp')          # => #<Pathname:lib/u.tmp>
  # link_pn.symlink?                         # => false
  # # Create link.
  # link_pn.make_symlink(target_pn)
  # link_pn.symlink?                         # => true
  # link_pn.delete                           # Clean up.
  # ```
  #
  def symlink?() FileTest.symlink?(@path) end

  # See <tt>FileTest.writable?</tt>.
  def writable?() FileTest.writable?(@path) end

  # See <tt>FileTest.world_writable?</tt>.
  def world_writable?() File.world_writable?(@path) end

  # See <tt>FileTest.writable_real?</tt>.
  def writable_real?() FileTest.writable_real?(@path) end

  # See <tt>FileTest.zero?</tt>.
  def zero?() FileTest.zero?(@path) end
end


class Pathname
  # call-seq:
  #   glob(patterns, base: '.', flags: 0, sort: true) → array_of_pathnames
  #   glob(patterns, base: '.', flags: 0, sort: true) {|pathname| ... } → nil
  #
  # Selects filesystem entries
  # based on the given keyword arguments +base+, +flags+, and +sort+;
  # see {Filename Globbing}[rdoc-ref:file/filename_globbing.md].
  #
  # With no block given, returns an array of pathnames,
  # each based on a selected filesystem entry.
  #
  # With a block given, calls the block with pathnames,
  # each based on a selected filesytem entry.
  #
  def Pathname.glob(*args, **kwargs) # :yield: pathname
    if block_given?
      Dir.glob(*args, **kwargs) {|f| yield self.new(f) }
    else
      Dir.glob(*args, **kwargs).map {|f| self.new(f) }
    end
  end

  # Returns or yields Pathname objects.
  #
  #  Pathname("ruby-2.4.2").glob("R*.md")
  #  #=> [#<Pathname:ruby-2.4.2/README.md>, #<Pathname:ruby-2.4.2/README.ja.md>]
  #
  # See Dir.glob.
  # This method uses the +base+ keyword argument of Dir.glob.
  def glob(*args, **kwargs) # :yield: pathname
    if block_given?
      Dir.glob(*args, **kwargs, base: @path) {|f| yield self + f }
    else
      Dir.glob(*args, **kwargs, base: @path).map {|f| self + f }
    end
  end

  # call-seq:
  #   Pathname.getwd -> new_pathname
  #
  # Returns a new \Pathname object containing the path to the current working directory
  # (equivalent to <tt>Pathname.new(Dir.getwd)</tt>):
  #
  #   Pathname.getwd # => #<Pathname:/home>
  #
  def Pathname.getwd() self.new(Dir.getwd) end
  class << self
    alias pwd getwd
  end

  # :markup: markdown
  #
  # call-seq:
  #   entries -> array_of_pathnames
  #
  # Returns an array of pathnames,
  # one for each entry in the directory represented by `self`:
  #
  # ```ruby
  # Pathname('.').entries.take(5)
  # # =>
  # # [#<Pathname:.>,
  # #  #<Pathname:..>,
  # #  #<Pathname:gc.rb>,
  # #  #<Pathname:yjit.rb>,
  # #  #<Pathname:iseq.h>]
  # ```
  #
  def entries() Dir.entries(@path).map {|f| self.class.new(f) } end

  # :markup: markdown
  #
  # call-seq:
  #   each_entry {|entry| ... } -> nil
  #   each_entry -> new_enumerator
  #
  # With a block given,
  # yields a new pathname for each entry
  # in the entry represented by `self`;
  # returns `nil`:
  #
  # ```ruby
  # Pathname('include').each_entry {|entry| p entry }
  # # #<Pathname:ruby>
  # # #<Pathname:..>
  # # #<Pathname:ruby.h>
  # # #<Pathname:.>
  # # => nil
  # ```
  #
  # With no block given, returns a new Enumerator.
  def each_entry(&block) # :yield: pathname
    return to_enum(__method__) unless block_given?
    Dir.foreach(@path) {|f| yield self.class.new(f) }
  end

  # :markup: markdown
  #
  # call-seq:
  #    mkdir(permissions = 0755) -> 0
  #
  # Creates a directory in the underlying file system
  # at the path in `self`, with the given `permissions`;
  # see {File Permissions}[rdoc-ref:File@File+Permissions]:
  #
  # ```ruby
  # Dir.mkdir('foo')
  # File.stat(Dir.new('foo')).mode.to_s(8) # => "40775"
  # Dir.mkdir('bar', 0644)
  # File.stat(Dir.new('bar')).mode.to_s(8) # => "40644"
  # Dir.rmdir('foo')
  # Dir.rmdir('bar')
  # ```
  #
  # Argument `permissions` is ignored on Windows.
  def mkdir(...) Dir.mkdir(@path, ...) end

  # See <tt>Dir.rmdir</tt>.  Remove the referenced directory.
  def rmdir() Dir.rmdir(@path) end

  # :markup: markdown
  #
  # call-seq:
  #   opendir {|dir| ... } -> object
  #   opendir -> dir
  #
  # Creates a Dir object `dir` for the directory at the path represented by `self`;
  # opens `dir`.
  #
  # With a block given, calls the block with `dir`;
  # on block exit, closes `dir` and returns the block's return value:
  #
  # ```ruby
  # pn = Pathname('.')
  # pn.opendir {|dir| dir.entries.take(3) }
  # # => ["README.md", "html", ".git"]
  # ```
  #
  # With no block given, returns the open directory `dir`:
  #
  # ```ruby
  # dir = pn.opendir    # => #<Dir:.>
  # dir.entries.take(3) # => ["README.md", "html", ".git"]
  # dir.close
  # ```
  #
  def opendir(&block) # :yield: dir
    Dir.open(@path, &block)
  end
end

class Pathname    # * mixed *
  #
  # :markup: markdown
  #
  # call-seq:
  #   unlink -> 1 or 0
  #
  # Removes the file or directory represented by `self`, using:
  #
  # - File.unlink, if `self` represents a file; returns `1`.
  # - Dir.unlink, if `self` represents a directory; returns `0`.
  #
  # Examples:
  #
  # ```ruby
  # Pathname(Tempfile.create).unlink   # => 1
  # Pathname(Pathname.mktmpdir).unlink # => 0
  # ```
  #
  def unlink()
    Dir.unlink @path
  rescue Errno::ENOTDIR
    File.unlink @path
  end
  alias delete unlink
end

class Pathname
  undef =~ if Kernel.method_defined?(:=~)
end

module Kernel
  # Creates a Pathname object.
  def Pathname(path) # :doc:
    return path if Pathname === path
    Pathname.new(path)
  end
  module_function :Pathname
end
