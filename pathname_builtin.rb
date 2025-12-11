# frozen_string_literal: true
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

#
# Pathname represents the name of a file or directory on the filesystem,
# but not the file itself.
#
# The pathname depends on the Operating System: Unix, Windows, etc.
# This library works with pathnames of local OS, however non-Unix pathnames
# are supported experimentally.
#
# A Pathname can be relative or absolute.  It's not until you try to
# reference the file that it even matters whether the file exists or not.
#
# Pathname is immutable.  It has no method for destructive update.
#
# The goal of this class is to manipulate file path information in a neater
# way than standard Ruby provides.  The examples below demonstrate the
# difference.
#
# *All* functionality from File, FileTest, and some from Dir and FileUtils is
# included, in an unsurprising way.  It is essentially a facade for all of
# these, and more.
#
# == Examples
#
# === Example 1: Using Pathname
#
#   require 'pathname'
#   pn = Pathname.new("/usr/bin/ruby")
#   size = pn.size              # 27662
#   isdir = pn.directory?       # false
#   dir  = pn.dirname           # Pathname:/usr/bin
#   base = pn.basename          # Pathname:ruby
#   dir, base = pn.split        # [Pathname:/usr/bin, Pathname:ruby]
#   data = pn.read
#   pn.open { |f| _ }
#   pn.each_line { |line| _ }
#
# === Example 2: Using standard Ruby
#
#   pn = "/usr/bin/ruby"
#   size = File.size(pn)        # 27662
#   isdir = File.directory?(pn) # false
#   dir  = File.dirname(pn)     # "/usr/bin"
#   base = File.basename(pn)    # "ruby"
#   dir, base = File.split(pn)  # ["/usr/bin", "ruby"]
#   data = File.read(pn)
#   File.open(pn) { |f| _ }
#   File.foreach(pn) { |line| _ }
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

  if File::FNM_SYSCASE.nonzero?
    # Avoid #zero? here because #casecmp can return nil.
    private def same_paths?(a, b) a.casecmp(b) == 0 end
  else
    private def same_paths?(a, b) a == b end
  end

  attr_reader :path
  protected :path

  # :startdoc:

  #
  # Create a Pathname object from the given String (or String-like object).
  # If +path+ contains a NUL character (<tt>\0</tt>), an ArgumentError is raised.
  #
  def initialize(path)
    @path = File.path(path).dup
  rescue TypeError => e
    raise e.class, "Pathname.new requires a String, #to_path or #to_str", cause: nil
  end

  #
  # Freze self.
  #
  def freeze
    super
    @path.freeze
    self
  end

  #
  # Compare this pathname with +other+.  The comparison is string-based.
  # Be aware that two different paths (<tt>foo.txt</tt> and <tt>./foo.txt</tt>)
  # can refer to the same file.
  #
  def ==(other)
    return false unless Pathname === other
    other.path == @path
  end
  alias === ==
  alias eql? ==

  unless method_defined?(:<=>, false)
    # Provides for comparing pathnames, case-sensitively.
    def <=>(other)
      return nil unless Pathname === other
      @path.tr('/', "\0") <=> other.path.tr('/', "\0")
    end
  end

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

  unless method_defined?(:sub, false)
    # Return a pathname which is substituted by String#sub.
    def sub(pattern, *args, **kwargs, &block)
      if block
        path = @path.sub(pattern, *args, **kwargs) {|*sub_args|
          begin
            old = Thread.current[:pathname_sub_matchdata]
            Thread.current[:pathname_sub_matchdata] = $~
            eval("$~ = Thread.current[:pathname_sub_matchdata]", block.binding)
          ensure
            Thread.current[:pathname_sub_matchdata] = old
          end
          yield(*sub_args)
        }
      else
        path = @path.sub(pattern, *args, **kwargs)
      end
      self.class.new(path)
    end
  end

  # Return a pathname with +repl+ added as a suffix to the basename.
  #
  # If self has no extension part, +repl+ is appended.
  #
  #	Pathname.new('/usr/bin/shutdown').sub_ext('.rb')
  #	    #=> #<Pathname:/usr/bin/shutdown.rb>
  def sub_ext(repl)
    ext = File.extname(@path)

    # File.extname("foo.bar:stream") returns ".bar" on NTFS and not ".bar:stream"
    # (see ruby_enc_find_extname()).
    # The behavior of Pathname#sub_ext is to replace everything
    # from the start of the extname until the end of the path with repl.
    unless @path.end_with?(ext)
      ext = @path[@path.rindex(ext)..]
    end

    self.class.new(@path.chomp(ext) + repl)
  end

  if File::ALT_SEPARATOR
    # Separator list string.
    SEPARATOR_LIST = Regexp.quote "#{File::ALT_SEPARATOR}#{File::SEPARATOR}"
    # Regexp that matches a separator.
    SEPARATOR_PAT = /[#{SEPARATOR_LIST}]/
  else
    SEPARATOR_LIST = Regexp.quote File::SEPARATOR
    SEPARATOR_PAT = /#{SEPARATOR_LIST}/
  end
  SEPARATOR_LIST.freeze
  SEPARATOR_PAT.freeze
  private_constant :SEPARATOR_LIST, :SEPARATOR_LIST

  if File.dirname('A:') == 'A:.' # DOSish drive letter
    # Regexp that matches an absolute path.
    ABSOLUTE_PATH = /\A(?:[A-Za-z]:|#{SEPARATOR_PAT})/
  else
    ABSOLUTE_PATH = /\A#{SEPARATOR_PAT}/
  end
  ABSOLUTE_PATH.freeze
  private_constant :ABSOLUTE_PATH

  # :startdoc:

  # Creates a full path, including any intermediate directories that don't yet
  # exist.
  #
  # See FileUtils.mkpath and FileUtils.mkdir_p
  def mkpath(mode: nil)
    path = @path == '/' ? @path : @path.chomp('/')

    stack = []
    until File.directory?(path) || File.dirname(path) == path
      stack.push path
      path = File.dirname(path)
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

  # chop_basename(path) -> [pre-basename, basename] or nil
  def chop_basename(path) # :nodoc:
    base = File.basename(path)
    if /\A#{SEPARATOR_PAT}?\z/o.match?(base)
      return nil
    else
      return path[0, path.rindex(base)], base
    end
  end
  private :chop_basename

  # split_names(path) -> prefix, [name, ...]
  def split_names(path) # :nodoc:
    names = []
    while r = chop_basename(path)
      path, basename = r
      names.unshift basename
    end
    return path, names
  end
  private :split_names

  def prepend_prefix(prefix, relpath) # :nodoc:
    if relpath.empty?
      File.dirname(prefix)
    elsif SEPARATOR_PAT.match?(prefix)
      prefix = File.dirname(prefix)
      prefix = File.join(prefix, "") if File.basename(prefix + 'a') != 'a'
      prefix + relpath
    else
      prefix + relpath
    end
  end
  private :prepend_prefix

  # Returns clean pathname of +self+ with consecutive slashes and useless dots
  # removed.  The filesystem is not accessed.
  #
  # If +consider_symlink+ is +true+, then a more conservative algorithm is used
  # to avoid breaking symbolic linkages.  This may retain more +..+
  # entries than absolutely necessary, but without accessing the filesystem,
  # this can't be avoided.
  #
  # See Pathname#realpath.
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
    if SEPARATOR_PAT.match?(File.basename(pre))
      names.shift while names[0] == '..'
    end
    self.class.new(prepend_prefix(pre, File.join(*names)))
  end
  private :cleanpath_aggressive

  # has_trailing_separator?(path) -> bool
  def has_trailing_separator?(path) # :nodoc:
    if r = chop_basename(path)
      pre, basename = r
      pre.length + basename.length < path.length
    else
      false
    end
  end
  private :has_trailing_separator?

  # add_trailing_separator(path) -> path
  def add_trailing_separator(path) # :nodoc:
    if File.basename(path + 'a') == 'a'
      path
    else
      File.join(path, "") # xxx: Is File.join is appropriate to add separator?
    end
  end
  private :add_trailing_separator

  def del_trailing_separator(path) # :nodoc:
    if r = chop_basename(path)
      pre, basename = r
      pre + basename
    elsif /#{SEPARATOR_PAT}+\z/o =~ path
      $` + File.dirname(path)[/#{SEPARATOR_PAT}*\z/o]
    else
      path
    end
  end
  private :del_trailing_separator

  def cleanpath_conservative # :nodoc:
    path = @path
    names = []
    pre = path
    while r = chop_basename(pre)
      pre, base = r
      names.unshift base if base != '.'
    end
    pre.tr!(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
    if SEPARATOR_PAT.match?(File.basename(pre))
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

  # Returns the parent directory.
  #
  # This is same as <code>self + '..'</code>.
  def parent
    self + '..'
  end

  # Returns +true+ if +self+ points to a mountpoint.
  def mountpoint?
    begin
      stat1 = self.lstat
      stat2 = self.parent.lstat
      stat1.dev != stat2.dev || stat1.ino == stat2.ino
    rescue Errno::ENOENT
      false
    end
  end

  #
  # Predicate method for root directories.  Returns +true+ if the
  # pathname consists of consecutive slashes.
  #
  # It doesn't access the filesystem.  So it may return +false+ for some
  # pathnames which points to roots such as <tt>/usr/..</tt>.
  #
  def root?
    chop_basename(@path) == nil && SEPARATOR_PAT.match?(@path)
  end

  # Predicate method for testing whether a path is absolute.
  #
  # It returns +true+ if the pathname begins with a slash.
  #
  #   p = Pathname.new('/im/sure')
  #   p.absolute?
  #       #=> true
  #
  #   p = Pathname.new('not/so/sure')
  #   p.absolute?
  #       #=> false
  def absolute?
    ABSOLUTE_PATH.match? @path
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

  #
  # Iterates over each component of the path.
  #
  #   Pathname.new("/usr/bin/ruby").each_filename {|filename| ... }
  #     # yields "usr", "bin", and "ruby".
  #
  # Returns an Enumerator if no block was given.
  #
  #   enum = Pathname.new("/usr/bin/ruby").each_filename
  #     # ... do stuff ...
  #   enum.each { |e| ... }
  #     # yields "usr", "bin", and "ruby".
  #
  def each_filename # :yield: filename
    return to_enum(__method__) unless block_given?
    _, names = split_names(@path)
    names.each {|filename| yield filename }
    nil
  end

  # Iterates over and yields a new Pathname object
  # for each element in the given path in descending order.
  #
  #  Pathname.new('/path/to/some/file.rb').descend {|v| p v}
  #     #<Pathname:/>
  #     #<Pathname:/path>
  #     #<Pathname:/path/to>
  #     #<Pathname:/path/to/some>
  #     #<Pathname:/path/to/some/file.rb>
  #
  #  Pathname.new('path/to/some/file.rb').descend {|v| p v}
  #     #<Pathname:path>
  #     #<Pathname:path/to>
  #     #<Pathname:path/to/some>
  #     #<Pathname:path/to/some/file.rb>
  #
  # Returns an Enumerator if no block was given.
  #
  #   enum = Pathname.new("/usr/bin/ruby").descend
  #     # ... do stuff ...
  #   enum.each { |e| ... }
  #     # yields Pathnames /, /usr, /usr/bin, and /usr/bin/ruby.
  #
  # It doesn't access the filesystem.
  #
  def descend
    return to_enum(__method__) unless block_given?
    vs = []
    ascend {|v| vs << v }
    vs.reverse_each {|v| yield v }
    nil
  end

  # Iterates over and yields a new Pathname object
  # for each element in the given path in ascending order.
  #
  #  Pathname.new('/path/to/some/file.rb').ascend {|v| p v}
  #     #<Pathname:/path/to/some/file.rb>
  #     #<Pathname:/path/to/some>
  #     #<Pathname:/path/to>
  #     #<Pathname:/path>
  #     #<Pathname:/>
  #
  #  Pathname.new('path/to/some/file.rb').ascend {|v| p v}
  #     #<Pathname:path/to/some/file.rb>
  #     #<Pathname:path/to/some>
  #     #<Pathname:path/to>
  #     #<Pathname:path>
  #
  # Returns an Enumerator if no block was given.
  #
  #   enum = Pathname.new("/usr/bin/ruby").ascend
  #     # ... do stuff ...
  #   enum.each { |e| ... }
  #     # yields Pathnames /usr/bin/ruby, /usr/bin, /usr, and /.
  #
  # It doesn't access the filesystem.
  #
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

  #
  # Appends a pathname fragment to +self+ to produce a new Pathname object.
  # Since +other+ is considered as a path relative to +self+, if +other+ is
  # an absolute path, the new Pathname object is created from just +other+.
  #
  #   p1 = Pathname.new("/usr")      # Pathname:/usr
  #   p2 = p1 + "bin/ruby"           # Pathname:/usr/bin/ruby
  #   p3 = p1 + "/etc/passwd"        # Pathname:/etc/passwd
  #
  #   # / is aliased to +.
  #   p4 = p1 / "bin/ruby"           # Pathname:/usr/bin/ruby
  #   p5 = p1 / "/etc/passwd"        # Pathname:/etc/passwd
  #
  # This method doesn't access the file system; it is pure string manipulation.
  #
  def +(other)
    other = Pathname.new(other) unless Pathname === other
    Pathname.new(plus(@path, other.path))
  end
  alias / +

  def plus(path1, path2) # -> path # :nodoc:
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
    if !r1 && (r1 = SEPARATOR_PAT.match?(File.basename(prefix1)))
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

  #
  # Joins the given pathnames onto +self+ to create a new Pathname object.
  # This is effectively the same as using Pathname#+ to append +self+ and
  # all arguments sequentially.
  #
  #   path0 = Pathname.new("/usr")                # Pathname:/usr
  #   path0 = path0.join("bin/ruby")              # Pathname:/usr/bin/ruby
  #       # is the same as
  #   path1 = Pathname.new("/usr") + "bin/ruby"   # Pathname:/usr/bin/ruby
  #   path0 == path1
  #       #=> true
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

  #
  # Returns the children of the directory (files and subdirectories, not
  # recursive) as an array of Pathname objects.
  #
  # By default, the returned pathnames will have enough information to access
  # the files. If you set +with_directory+ to +false+, then the returned
  # pathnames will contain the filename only.
  #
  # For example:
  #   pn = Pathname("/usr/lib/ruby/1.8")
  #   pn.children
  #       # -> [ Pathname:/usr/lib/ruby/1.8/English.rb,
  #              Pathname:/usr/lib/ruby/1.8/Env.rb,
  #              Pathname:/usr/lib/ruby/1.8/abbrev.rb, ... ]
  #   pn.children(false)
  #       # -> [ Pathname:English.rb, Pathname:Env.rb, Pathname:abbrev.rb, ... ]
  #
  # Note that the results never contain the entries +.+ and +..+ in
  # the directory because they are not children.
  #
  def children(with_directory=true)
    with_directory = false if @path == '.'
    result = []
    Dir.foreach(@path) {|e|
      next if e == '.' || e == '..'
      if with_directory
        result << self.class.new(File.join(@path, e))
      else
        result << self.class.new(e)
      end
    }
    result
  end

  # Iterates over the children of the directory
  # (files and subdirectories, not recursive).
  #
  # It yields Pathname object for each child.
  #
  # By default, the yielded pathnames will have enough information to access
  # the files.
  #
  # If you set +with_directory+ to +false+, then the returned pathnames will
  # contain the filename only.
  #
  #   Pathname("/usr/local").each_child {|f| p f }
  #   #=> #<Pathname:/usr/local/share>
  #   #   #<Pathname:/usr/local/bin>
  #   #   #<Pathname:/usr/local/games>
  #   #   #<Pathname:/usr/local/lib>
  #   #   #<Pathname:/usr/local/include>
  #   #   #<Pathname:/usr/local/sbin>
  #   #   #<Pathname:/usr/local/src>
  #   #   #<Pathname:/usr/local/man>
  #
  #   Pathname("/usr/local").each_child(false) {|f| p f }
  #   #=> #<Pathname:share>
  #   #   #<Pathname:bin>
  #   #   #<Pathname:games>
  #   #   #<Pathname:lib>
  #   #   #<Pathname:include>
  #   #   #<Pathname:sbin>
  #   #   #<Pathname:src>
  #   #   #<Pathname:man>
  #
  # Note that the results never contain the entries +.+ and +..+ in
  # the directory because they are not children.
  #
  # See Pathname#children
  #
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
  #
  # #each_line iterates over the line in the file.  It yields a String object
  # for each line.
  #
  # This method has existed since 1.8.1.
  #
  def each_line(...) # :yield: line
    File.foreach(@path, ...)
  end

  # See <tt>File.read</tt>.  Returns all data from the file, or the first +N+ bytes
  # if specified.
  def read(...) File.read(@path, ...) end

  # See <tt>File.binread</tt>.  Returns all the bytes from the file, or the first +N+
  # if specified.
  def binread(...) File.binread(@path, ...) end

  # See <tt>File.readlines</tt>.  Returns all the lines from the file.
  def readlines(...) File.readlines(@path, ...) end

  # See <tt>File.sysopen</tt>.
  def sysopen(...) File.sysopen(@path, ...) end

  # Writes +contents+ to the file. See <tt>File.write</tt>.
  def write(...) File.write(@path, ...) end

  # Writes +contents+ to the file, opening it in binary mode.
  #
  # See File.binwrite.
  def binwrite(...) File.binwrite(@path, ...) end

  # See <tt>File.atime</tt>.  Returns last access time.
  def atime() File.atime(@path) end

  # Returns the birth time for the file.
  # If the platform doesn't have birthtime, raises NotImplementedError.
  #
  # See File.birthtime.
  def birthtime() File.birthtime(@path) end

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
  def fnmatch(pattern, ...) File.fnmatch(pattern, @path, ...) end

  # See <tt>File.fnmatch?</tt> (same as #fnmatch).
  def fnmatch?(pattern, ...) File.fnmatch?(pattern, @path, ...) end

  # See <tt>File.ftype</tt>.  Returns "type" of file ("file", "directory",
  # etc).
  def ftype() File.ftype(@path) end

  # See <tt>File.link</tt>.  Creates a hard link.
  def make_link(old) File.link(old, @path) end

  # See <tt>File.open</tt>.  Opens the file for reading or writing.
  def open(...) # :yield: file
    File.open(@path, ...)
  end

  # See <tt>File.readlink</tt>.  Read symbolic link.
  def readlink() self.class.new(File.readlink(@path)) end

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

  # Update the access and modification times of the file.
  #
  # Same as Pathname#utime, but does not follow symbolic links.
  #
  # See File.lutime.
  def lutime(atime, mtime) File.lutime(atime, mtime, @path) end

  # See <tt>File.basename</tt>.  Returns the last component of the path.
  def basename(...) self.class.new(File.basename(@path, ...)) end

  # See <tt>File.dirname</tt>.  Returns all but the last component of the path.
  def dirname() self.class.new(File.dirname(@path)) end

  # See <tt>File.extname</tt>.  Returns the file's extension.
  def extname() File.extname(@path) end

  # See <tt>File.expand_path</tt>.
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

  # See <tt>FileTest.blockdev?</tt>.
  def blockdev?() FileTest.blockdev?(@path) end

  # See <tt>FileTest.chardev?</tt>.
  def chardev?() FileTest.chardev?(@path) end

  # Tests the file is empty.
  #
  # See Dir#empty? and FileTest.empty?.
  def empty?
    if FileTest.directory?(@path)
      Dir.empty?(@path)
    else
      File.empty?(@path)
    end
  end

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

  # See <tt>FileTest.symlink?</tt>.
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


class Pathname    # * Dir *
  # See <tt>Dir.glob</tt>.  Returns or yields Pathname objects.
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

  # See <tt>Dir.getwd</tt>.  Returns the current working directory as a Pathname.
  def Pathname.getwd() self.new(Dir.getwd) end
  class << self
    alias pwd getwd
  end

  # Return the entries (files and subdirectories) in the directory, each as a
  # Pathname object.
  def entries() Dir.entries(@path).map {|f| self.class.new(f) } end

  # Iterates over the entries (files and subdirectories) in the directory.  It
  # yields a Pathname object for each entry.
  #
  # This method has existed since 1.8.1.
  def each_entry(&block) # :yield: pathname
    return to_enum(__method__) unless block_given?
    Dir.foreach(@path) {|f| yield self.class.new(f) }
  end

  # See <tt>Dir.mkdir</tt>.  Create the referenced directory.
  def mkdir(...) Dir.mkdir(@path, ...) end

  # See <tt>Dir.rmdir</tt>.  Remove the referenced directory.
  def rmdir() Dir.rmdir(@path) end

  # See <tt>Dir.open</tt>.
  def opendir(&block) # :yield: dir
    Dir.open(@path, &block)
  end
end

class Pathname    # * mixed *
  # Removes a file or directory, using <tt>File.unlink</tt> or
  # <tt>Dir.unlink</tt> as necessary.
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
