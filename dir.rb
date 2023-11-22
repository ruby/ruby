# An object of class \Dir represents a directory in the underlying file system.
#
# It consists mainly of:
#
# - A string _path_, given when the object is created,
#   that specifies a directory in the underlying file system;
#   method #path returns the path.
# - A collection of string <i>entry names</i>,
#   each of which is the name of a directory or file in the underlying file system;
#   the entry names may be retrieved
#   in an {array-like fashion}[rdoc-ref:Dir@Dir+As+Array-Like]
#   or in a {stream-like fashion}[rdoc-ref:Dir@Dir+As+Stream-Like].
#
# == About the Examples
#
# Some examples on this page use this simple file tree:
#
#   example/
#   ├── config.h
#   ├── lib/
#   │   ├── song/
#   │   │   └── karaoke.rb
#   │   └── song.rb
#   └── main.rb
#
# Others use the file tree for the
# {Ruby project itself}[https://github.com/ruby/ruby].
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
# but may be closed manually (using method #close),
# and will be closed on block exit if created by Dir.open called with a block.
# The closed stream may not be further manipulated,
# and may not be reopened.
#
# The stream has a _position_, which is the index of an entry in the directory:
#
# - The initial position is zero (before the first entry).
# - \Method #tell (aliased as #pos) returns the position.
# - \Method #pos= sets the position (but ignores a value outside the stream),
#   and returns the position.
# - \Method #seek is like #pos=, but returns +self+ (convenient for chaining).
# - \Method #read, if not at end-of-stream, reads the next entry and increments
#   the position;
#   if at end-of-stream, does not increment the position.
# - \Method #rewind sets the position to zero.
#
# Examples (using the {simple file tree}[rdoc-ref:Dir@About+the+Examples]):
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
  # call-seq:
  #   Dir.open(dirpath) -> dir
  #   Dir.open(dirpath, encoding: nil) -> dir
  #   Dir.open(dirpath) {|dir| ... } -> object
  #   Dir.open(dirpath, encoding: nil) {|dir| ... } -> object
  #
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

  # call-seq:
  #   Dir.new(dirpath) -> dir
  #   Dir.new(dirpath, encoding: nil) -> dir
  #
  # Returns a new \Dir object for the directory at +dirpath+:
  #
  #   Dir.new('.') # => #<Dir:.>
  #
  # The value given with optional keyword argument +encoding+
  # specifies the encoding for the directory entry names;
  # if +nil+ (the default), the file system's encoding is used:
  #
  #   Dir.new('.').read.encoding                       # => #<Encoding:UTF-8>
  #   Dir.new('.', encoding: 'US-ASCII').read.encoding # => #<Encoding:US-ASCII>
  #
  def initialize(name, encoding: nil)
    Primitive.dir_initialize(name, encoding)
  end

  # call-seq:
  #   Dir[*patterns, base: nil, sort: true] -> array
  #
  # Calls Dir.glob with argument +patterns+
  # and the values of keyword arguments +base+ and +sort+;
  # returns the array of selected entry names.
  #
  def self.[](*args, base: nil, sort: true)
    Primitive.dir_s_aref(args, base, sort)
  end

  # call-seq:
  #   Dir.glob(*patterns, flags: 0, base: nil, sort: true) -> array
  #   Dir.glob(*patterns, flags: 0, base: nil, sort: true) {|entry_name| ... } -> nil
  #
  # Forms an array _entry_names_ of the entry names selected by the arguments.
  #
  # Argument +patterns+ is a string pattern or an array of string patterns;
  # note that these are not regexps; see below.
  #
  # Notes for the following examples:
  #
  # - <tt>'*'</tt> is the pattern that matches any entry name
  #   except those that begin with <tt>'.'</tt>.
  # - We use method Array#take to shorten returned arrays
  #   that otherwise would be very large.
  #
  # With no block, returns array _entry_names_;
  # example (using the {simple file tree}[rdoc-ref:Dir@About+the+Examples]):
  #
  #   Dir.glob('*') # => ["config.h", "lib", "main.rb"]
  #
  # With a block, calls the block with each of the _entry_names_
  # and returns +nil+:
  #
  #   Dir.glob('*') {|entry_name| puts entry_name } # => nil
  #
  # Output:
  #
  #   config.h
  #   lib
  #   main.rb
  #
  # If optional keyword argument +flags+ is given,
  # the value modifies the matching; see below.
  #
  # If optional keyword argument +base+ is given,
  # its value specifies the base directory.
  # Each pattern string specifies entries relative to the base directory;
  # the default is <tt>'.'</tt>.
  # The base directory is not prepended to the entry names in the result:
  #
  #   Dir.glob(pattern, base: 'lib').take(5)
  #   # => ["abbrev.gemspec", "abbrev.rb", "base64.gemspec", "base64.rb", "benchmark.gemspec"]
  #   Dir.glob(pattern, base: 'lib/irb').take(5)
  #   # => ["cmd", "color.rb", "color_printer.rb", "completion.rb", "context.rb"]
  #
  # If optional keyword +sort+ is given, its value specifies whether
  # the array is to be sorted; the default is +true+.
  # Passing value +false+ with that keyword disables sorting
  # (though the underlying file system may already have sorted the array).
  #
  # <b>Patterns</b>
  #
  # Each pattern string is expanded
  # according to certain metacharacters;
  # examples below use the {Ruby file tree}[rdoc-ref:Dir@About+the+Examples]:
  #
  # - <tt>'*'</tt>: Matches any substring in an entry name,
  #   similar in meaning to regexp <tt>/.*/mx</tt>;
  #   may be restricted by other values in the pattern strings:
  #
  #   - <tt>'*'</tt> matches all entry names:
  #
  #       Dir.glob('*').take(3)  # => ["BSDL", "CONTRIBUTING.md", "COPYING"]
  #
  #   - <tt>'c*'</tt> matches entry names beginning with <tt>'c'</tt>:
  #
  #       Dir.glob('c*').take(3) # => ["CONTRIBUTING.md", "COPYING", "COPYING.ja"]
  #
  #   - <tt>'*c'</tt> matches entry names ending with <tt>'c'</tt>:
  #
  #       Dir.glob('*c').take(3) # => ["addr2line.c", "array.c", "ast.c"]
  #
  #   - <tt>'\*c\*'</tt> matches entry names that contain <tt>'c'</tt>,
  #     even at the beginning or end:
  #
  #       Dir.glob('*c*').take(3) # => ["CONTRIBUTING.md", "COPYING", "COPYING.ja"]
  #
  #   Does not match Unix-like hidden entry names ("dot files").
  #   To include those in the matched entry names,
  #   use flag IO::FNM_DOTMATCH or something like <tt>'{*,.*}'</tt>.
  #
  #  - <tt>'**'</tt>: Matches entry names recursively
  #    if followed by  the slash character <tt>'/'</tt>:
  #
  #      Dir.glob('**/').take(3) # => ["basictest/", "benchmark/", "benchmark/gc/"]
  #
  #    If the string pattern contains other characters
  #    or is not followed by a slash character,
  #    it is equivalent to <tt>'*'</tt>.
  #
  # - <tt>'?'</tt> Matches any single character;
  #   similar in meaning to regexp <tt>/./</tt>:
  #
  #     Dir.glob('io.?') # => ["io.c"]
  #
  # - <tt>'[_set_]'</tt>: Matches any one character in the string _set_;
  #   behaves like a {Regexp character class}[rdoc-ref:Regexp@Character+Classes],
  #   including set negation (<tt>'[^a-z]'</tt>):
  #
  #     Dir.glob('*.[a-z][a-z]').take(3)
  #     # => ["CONTRIBUTING.md", "COPYING.ja", "KNOWNBUGS.rb"]
  #
  # - <tt>'{_abc_,_xyz_}'</tt>:
  #   Matches either string _abc_ or string _xyz_;
  #   behaves like {Regexp alternation}[rdoc-ref:Regexp@Alternation]:
  #
  #     Dir.glob('{LEGAL,BSDL}') # => ["LEGAL", "BSDL"]
  #
  #   More than two alternatives may be given.
  #
  # - <tt>\\</tt>: Escapes the following metacharacter.
  #
  #   Note that on Windows, the backslash character may not be used
  #   in a string pattern:
  #   <tt>Dir['c:\\foo*']</tt> will not work, use <tt>Dir['c:/foo*']</tt> instead.
  #
  # More examples (using the {simple file tree}[rdoc-ref:Dir@About+the+Examples]):
  #
  #   # We're in the example directory.
  #   File.basename(Dir.pwd) # => "example"
  #   Dir.glob('config.?')              # => ["config.h"]
  #   Dir.glob('*.[a-z][a-z]')          # => ["main.rb"]
  #   Dir.glob('*.[^r]*')               # => ["config.h"]
  #   Dir.glob('*.{rb,h}')              # => ["main.rb", "config.h"]
  #   Dir.glob('*')                     # => ["config.h", "lib", "main.rb"]
  #   Dir.glob('*', File::FNM_DOTMATCH) # => [".", "config.h", "lib", "main.rb"]
  #   Dir.glob(["*.rb", "*.h"])         # => ["main.rb", "config.h"]
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
  # <b>Flags</b>
  #
  # If optional keyword argument +flags+ is given (the default is zero -- no flags),
  # its value should be the bitwise OR of one or more of the constants
  # defined in module File::Constants.
  #
  # Example:
  #
  #   flags = File::FNM_EXTGLOB | File::FNM_DOTMATCH
  #
  # Specifying flags can extend, restrict, or otherwise modify the matching.
  #
  # The flags for this method (other constants in File::Constants do not apply):
  #
  # - File::FNM_DOTMATCH:
  #   specifies that entry names beginning with <tt>'.'</tt>
  #   should be considered for matching:
  #
  #     Dir.glob('*').take(5)
  #     # => ["BSDL", "CONTRIBUTING.md", "COPYING", "COPYING.ja", "GPL"]
  #     Dir.glob('*', flags: File::FNM_DOTMATCH).take(5)
  #     # => [".", ".appveyor.yml", ".cirrus.yml", ".dir-locals.el", ".document"]
  #
  # - File::FNM_EXTGLOB:
  #   enables the pattern extension
  #   <tt>'{_a_,_b_}'</tt>, which matches pattern _a_ and pattern _b_;
  #   behaves like a
  #   {regexp union}[rdoc-ref:Regexp.union]
  #   (e.g., <tt>'(?:_a_|_b_)'</tt>):
  #
  #     pattern = '{LEGAL,BSDL}'
  #     Dir.glob(pattern)      # => ["LEGAL", "BSDL"]
  #
  # - File::FNM_NOESCAPE:
  #   specifies that escaping with the backslash character <tt>'\'</tt>
  #   is disabled; the character is not an escape character.
  #
  # - File::FNM_PATHNAME:
  #   specifies that metacharacters <tt>'*'</tt> and <tt>'?'</tt>
  #   do not match directory separators.
  #
  # - File::FNM_SHORTNAME:
  #   specifies that patterns may match short names if they exist; Windows only.
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
