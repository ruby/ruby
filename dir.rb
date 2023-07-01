# An object of class \Dir represents a directory in the underlying file systems.
#
# == About the Examples
#
# The file tree for the examples on this page:
#
#   example/
#   ├── config.h
#   ├── lib/
#   │   ├── song/
#   │   │   └── karaoke.rb
#   │   └── song.rb
#   └── main.rb
#
# == \Dir As \Array-Like
#
# A \Dir object is in some ways array-like:
#
# - It has instance methods #children, #each, and #each_child.
# - It includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here].
#
# == \Dir As Stream-Like
#
# A \Dir object is in some ways stream-like.
#
# The stream is initially open for reading,
# but may be closed (method Dir#close),
# and will be closed on block exit if created by Dir.open called with a block.
#
# The stream has a _position_, which is an index of an entry in the directory:
#
# - The initial position is zero.
# - \Method #tell (aliased as #pos) returns the position.
# - \Method #pos= sets the position (but ignores a value outside the stream),
#   and returns the position.
# - \Method #seek is like #pos, but returns +self+ (convenient for chaining).
# - \Method #read, if not at end-of-stream, reads the next entry and increments
#   the position;
#   if at end-of-stream, does not increment the position.
# - \Method #rewind sets the position to zero.
#
# Example:
#
#   dir = Dir.new('example') # => #<Dir:example>
#   dir.pos                  # => 0
#
#   dir.read # => "."
#   dir.read # => ".."
#   dir.read # => "config.h"
#   dir.read # => "lib"
#   dir.read # => "main.rb"
#   dir.pos  # => 5
#   dir.read # => nil
#   dir.pos  # => 5
#
#   dir.rewind # => #<Dir:example>
#   dir.pos    # => 0
#
#   dir.pos = 3 # => 3
#   dir.pos     # => 3
#
#   dir.seek(4) # => #<Dir:example>
#   dir.pos     # => 4
#
#   dir.close # => nil
#   dir.read  # Raises IOError.
#
# == What's Here
#
# First, what's elsewhere. \Class \Dir:
#
# - Inherits from {class Object}[rdoc-ref:Object@What-27s+Here].
# - Includes {module Enumerable}[rdoc-ref:Enumerable@What-27s+Here],
#   which provides dozens of additional methods.
#
# Here, class \Dir provides methods that are useful for:
#
# - {Reading}[rdoc-ref:Dir@Reading]
# - {Setting}[rdoc-ref:Dir@Setting]
# - {Querying}[rdoc-ref:Dir@Querying]
# - {Iterating}[rdoc-ref:Dir@Iterating]
# - {Other}[rdoc-ref:Dir@Other]
#
# === Reading
#
# - #close: Closes the directory stream for +self+.
# - #pos=: Sets the position in the directory stream for +self+.
# - #read: Reads and returns the next entry in the directory stream for +self+.
# - #rewind: Sets the position in the directory stream for +self+ to the first entry.
# - #seek: Sets the position in the directory stream for +self+
#   the entry at the given offset.
#
# === Setting
#
# - ::chdir: Changes the working directory of the current process
#   to the given directory.
# - ::chroot: Changes the file-system root for the current process
#   to the given directory.
#
# === Querying
#
# - ::[]: Same as ::glob without the ability to pass flags.
# - ::children: Returns an array of names of the children
#   (both files and directories) of the given directory,
#   but not including <tt>.</tt> or <tt>..</tt>.
# - ::empty?: Returns whether the given path is an empty directory.
# - ::entries: Returns an array of names of the children
#   (both files and directories) of the given directory,
#   including <tt>.</tt> and <tt>..</tt>.
# - ::exist?: Returns whether the given path is a directory.
# - ::getwd (aliased as #pwd): Returns the path to the current working directory.
# - ::glob: Returns an array of file paths matching the given pattern and flags.
# - ::home: Returns the home directory path for a given user or the current user.
# - #children: Returns an array of names of the children
#   (both files and directories) of +self+,
#   but not including <tt>.</tt> or <tt>..</tt>.
# - #fileno: Returns the integer file descriptor for +self+.
# - #path (aliased as #to_path): Returns the path used to create +self+.
# - #tell (aliased as #pos): Returns the integer position
#   in the directory stream for +self+.
#
# === Iterating
#
# - ::each_child: Calls the given block with each entry in the given directory,
#   but not including <tt>.</tt> or <tt>..</tt>.
# - ::foreach: Calls the given block with each entry in the given directory,
#   including <tt>.</tt> and <tt>..</tt>.
# - #each: Calls the given block with each entry in +self+,
#   including <tt>.</tt> and <tt>..</tt>.
# - #each_child: Calls the given block with each entry in +self+,
#   but not including <tt>.</tt> or <tt>..</tt>.
#
# === Other
#
# - ::mkdir: Creates a directory at the given path, with optional permissions.
# - ::new: Returns a new \Dir for the given path, with optional encoding.
# - ::open: Same as ::new, but if a block is given, yields the \Dir to the block,
#   closing it upon block exit.
# - ::unlink (aliased as ::delete and ::rmdir): Removes the given directory.
# - #inspect: Returns a string description of +self+.
#
class Dir
  # Creates a new \Dir object _dir_ for the directory at +dirpath+.
  #
  # With no block, the method equivalent to Dir.new(dirpath, encoding):
  #
  #   Dir.open('.') # => #<Dir:.>
  #
  # With a block given, the block is called with the created _dir_;
  # on block exit _dir_ is closed and the block's value is returned:
  #
  #   Dir.open('.') {|dir| dir.inspect } # => "#<Dir:.>"
  #
  # The value given with optional keyword argument +encoding+
  # specifies the encoding for the directory entry names;
  # if +nil+ (the default), the file system's encoding is used:
  #
  #   Dir.open('.').read.encoding                       # => #<Encoding:UTF-8>
  #   Dir.open('.', encoding: 'US-ASCII').read.encoding # => #<Encoding:US-ASCII>
  #
  def self.open(name, encoding: nil, &block)
    dir = Primitive.dir_s_open(name, encoding)
    if block
      begin
        yield dir
      ensure
        Primitive.dir_s_close(dir)
      end
    else
      dir
    end
  end

  # Returns a new \Dir object for the directory at +dirpath+:
  #
  #   Dir.new('.') # => #<Dir:.>
  #
  # The value given with optional keyword argument +encoding+
  # specifies the encoding for the directory entry names;
  # if +nil+ (the default), the file system's encoding is used:
  #
  #   Dir.new('.').read.encoding                     # => #<Encoding:UTF-8>
  #   Dir.new('.', encoding: 'US-ASCII').read.encoding # => #<Encoding:US-ASCII>
  #
  def initialize(name, encoding: nil)
    Primitive.dir_initialize(name, encoding)
  end

  # Calls Dir.glob with argument <tt>*dirpaths</tt>
  # and the values of keyword arguments +base+ and +sort+;
  # returns the array of selected entry names.
  #
  def self.[](*args, base: nil, sort: true)
    Primitive.dir_s_aref(args, base, sort)
  end

  # Forms an array of the entry names selected by the arguments.
  #
  # Argument +pattern+ is a pattern string or an array of pattern strings.
  #
  # With no block, returns an array of selected entry names;
  # with a block, calls the block with each selected entry name.
  #
  # Each pattern string (which is _not_ a regexp) is expanded
  # according to certain metacharacters:
  #
  # - <tt>'*'</tt>: Matches any substring in an entry name,
  #   similar in meaning to regexp <tt>/.*/mx</tt>;
  #   may be restricted by other values in the pattern strings:
  #
  #   - <tt>'*'</tt> matches all entry names.
  #   - <tt>'c*'</tt> matches entry names beginning with <tt>'c'</tt>.
  #   - <tt>'*c'</tt> matches entry names ending with <tt>'c'</tt>.
  #   - <tt>'\*c\*'</tt> matches entry names that contain <tt>'c'</tt>,
  #     even at the beginning or end.
  #
  #   Does not match Unix-like hidden entry names ("dotfiles").
  #   To include those in the matched entry names,
  #   use flag File::FNM_DOTMATCH or something like <tt>'{*,.*}'</tt>.
  #
  #  - <tt>'**'</tt>: Matches entry names recursively if followed by <tt>'/'</tt>.
  #    If the string pattern contains any other characters,
  #    it is equivalent to <tt>'*'</tt>.
  #
  # - <tt>'?'</tt> Matches any single character;
  #   similar in meaning to regexp <tt>/.{1}/</tt>.
  #
  # - <tt>'[_set_]'</tt>: Matches any one character in the string _set_;
  #   behaves like a {Regexp character class}[rdoc-ref:regexp.rdoc@Character+Classes],
  #   including set negation (<tt>'[^a-z]'</tt>).
  #
  # - <tt>'{_abc_,_xyz_}'</tt>:
  #   Matches either string _abc_ or string _xyz_;
  #   behaves like {Regexp alternation}[rdoc-ref:regexp.rdoc@Alternation],
  #   More than two alternatives may be given.
  #
  # - <tt>\\</tt>: Escapes the following metacharacter.
  #
  #   Note that on Windows, the backslash character may not be used
  #   in a string pattern:
  #   <tt>Dir['c:\\foo*']</tt> will not work, use <tt>Dir['c:/foo*']</tt> instead.
  #
  # If optional keyword argument +base+ is given,
  # each pattern string specifies entries relative to the specified directory;
  # the default is <tt>'.'</tt>.
  # The base directory is not prepended to the entry names in the result.
  #
  # If optional keyword +sort+ is given, its value specifies whether
  # the array is to be sorted;
  # the default is +true+.
  #
  # Examples:
  #
  #   Dir.glob('config.?')              # => ["config.h"]
  #   Dir.glob('*.[a-z][a-z]')          # => ["main.rb"]
  #   Dir.glob('*.[^r]*')               # => ["config.h"]
  #   Dir.glob('*.{rb,h}')              # => ["main.rb", "config.h"]
  #   Dir.glob('*')                     # => ["config.h", "lib", "main.rb"]
  #   Dir.glob('*', File::FNM_DOTMATCH) # => [".", "config.h", "lib", "main.rb"]
  #   Dir.glob(["*.rb", "*.h"])         # => ["main.rb", "config.h"]
  #
  #
  #   Dir.glob('**/*.rb')
  #   => ["lib/song/karaoke.rb", "lib/song.rb", "main.rb"]
  #
  #   Dir.glob('**/*.rb', base: 'lib')  #   => ["song/karaoke.rb", "song.rb"]
  #
  #   Dir.glob('**/lib')                # => ["lib"]
  #
  #   Dir.glob('**/lib/**/*.rb')        # => ["lib/song/karaoke.rb", "lib/song.rb"]
  #
  #   Dir.glob('**/lib/*.rb')           # => ["lib/song.rb"]
  #
  def self.glob(pattern, _flags = 0, flags: _flags, base: nil, sort: true)
    Primitive.dir_s_glob(pattern, flags, base, sort)
  end
end

class << File
  # call-seq:
  #    File.fnmatch( pattern, path, [flags] ) -> (true or false)
  #    File.fnmatch?( pattern, path, [flags] ) -> (true or false)
  #
  # Returns true if +path+ matches against +pattern+.  The pattern is not a
  # regular expression; instead it follows rules similar to shell filename
  # globbing.  It may contain the following metacharacters:
  #
  # <code>*</code>::
  #   Matches any file. Can be restricted by other values in the glob.
  #   Equivalent to <code>/.*/x</code> in regexp.
  #
  #   <code>*</code>::    Matches all regular files
  #   <code>c*</code>::   Matches all files beginning with <code>c</code>
  #   <code>*c</code>::   Matches all files ending with <code>c</code>
  #   <code>\*c*</code>:: Matches all files that have <code>c</code> in them
  #                       (including at the beginning or end).
  #
  #   To match hidden files (that start with a <code>.</code>) set the
  #   File::FNM_DOTMATCH flag.
  #
  # <code>**</code>::
  #   Matches directories recursively or files expansively.
  #
  # <code>?</code>::
  #   Matches any one character. Equivalent to <code>/.{1}/</code> in regexp.
  #
  # <code>[set]</code>::
  #   Matches any one character in +set+.  Behaves exactly like character sets
  #   in Regexp, including set negation (<code>[^a-z]</code>).
  #
  # <code>\\</code>::
  #   Escapes the next metacharacter.
  #
  # <code>{a,b}</code>::
  #   Matches pattern a and pattern b if File::FNM_EXTGLOB flag is enabled.
  #   Behaves like a Regexp union (<code>(?:a|b)</code>).
  #
  # +flags+ is a bitwise OR of the <code>FNM_XXX</code> constants. The same
  # glob pattern and flags are used by Dir::glob.
  #
  # Examples:
  #
  #    File.fnmatch('cat',       'cat')        #=> true  # match entire string
  #    File.fnmatch('cat',       'category')   #=> false # only match partial string
  #
  #    File.fnmatch('c{at,ub}s', 'cats')                    #=> false # { } isn't supported by default
  #    File.fnmatch('c{at,ub}s', 'cats', File::FNM_EXTGLOB) #=> true  # { } is supported on FNM_EXTGLOB
  #
  #    File.fnmatch('c?t',     'cat')          #=> true  # '?' match only 1 character
  #    File.fnmatch('c??t',    'cat')          #=> false # ditto
  #    File.fnmatch('c*',      'cats')         #=> true  # '*' match 0 or more characters
  #    File.fnmatch('c*t',     'c/a/b/t')      #=> true  # ditto
  #    File.fnmatch('ca[a-z]', 'cat')          #=> true  # inclusive bracket expression
  #    File.fnmatch('ca[^t]',  'cat')          #=> false # exclusive bracket expression ('^' or '!')
  #
  #    File.fnmatch('cat', 'CAT')                     #=> false # case sensitive
  #    File.fnmatch('cat', 'CAT', File::FNM_CASEFOLD) #=> true  # case insensitive
  #    File.fnmatch('cat', 'CAT', File::FNM_SYSCASE)  #=> true or false # depends on the system default
  #
  #    File.fnmatch('?',   '/', File::FNM_PATHNAME)  #=> false # wildcard doesn't match '/' on FNM_PATHNAME
  #    File.fnmatch('*',   '/', File::FNM_PATHNAME)  #=> false # ditto
  #    File.fnmatch('[/]', '/', File::FNM_PATHNAME)  #=> false # ditto
  #
  #    File.fnmatch('\?',   '?')                       #=> true  # escaped wildcard becomes ordinary
  #    File.fnmatch('\a',   'a')                       #=> true  # escaped ordinary remains ordinary
  #    File.fnmatch('\a',   '\a', File::FNM_NOESCAPE)  #=> true  # FNM_NOESCAPE makes '\' ordinary
  #    File.fnmatch('[\?]', '?')                       #=> true  # can escape inside bracket expression
  #
  #    File.fnmatch('*',   '.profile')                      #=> false # wildcard doesn't match leading
  #    File.fnmatch('*',   '.profile', File::FNM_DOTMATCH)  #=> true  # period by default.
  #    File.fnmatch('.*',  '.profile')                      #=> true
  #
  #    File.fnmatch('**/*.rb', 'main.rb')                  #=> false
  #    File.fnmatch('**/*.rb', './main.rb')                #=> false
  #    File.fnmatch('**/*.rb', 'lib/song.rb')              #=> true
  #    File.fnmatch('**.rb', 'main.rb')                    #=> true
  #    File.fnmatch('**.rb', './main.rb')                  #=> false
  #    File.fnmatch('**.rb', 'lib/song.rb')                #=> true
  #    File.fnmatch('*',     'dave/.profile')              #=> true
  #
  #    File.fnmatch('**/foo', 'a/b/c/foo', File::FNM_PATHNAME)     #=> true
  #    File.fnmatch('**/foo', '/a/b/c/foo', File::FNM_PATHNAME)    #=> true
  #    File.fnmatch('**/foo', 'c:/a/b/c/foo', File::FNM_PATHNAME)  #=> true
  #    File.fnmatch('**/foo', 'a/.b/c/foo', File::FNM_PATHNAME)    #=> false
  #    File.fnmatch('**/foo', 'a/.b/c/foo', File::FNM_PATHNAME | File::FNM_DOTMATCH) #=> true
  def fnmatch(pattern, path, flags = 0)
  end
  alias fnmatch? fnmatch
end if false
