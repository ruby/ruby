# Objects of class Dir are directory streams representing
# directories in the underlying file system. They provide a variety
# of ways to list directories and their contents. See also File.
#
# The directory used in these examples contains the two regular files
# (<code>config.h</code> and <code>main.rb</code>), the parent
# directory (<code>..</code>), and the directory itself
# (<code>.</code>).
#
# == What's Here
#
# First, what's elsewhere. \Class \Dir:
#
# - Inherits from {class Object}[Object.html#class-Object-label-What-27s+Here].
# - Includes {module Enumerable}[Enumerable.html#module-Enumerable-label-What-27s+Here],
#   which provides dozens of additional methods.
#
# Here, class \Dir provides methods that are useful for:
#
# - {Reading}[#class-Dir-label-Reading]
# - {Setting}[#class-Dir-label-Setting]
# - {Querying}[#class-Dir-label-Querying]
# - {Iterating}[#class-Dir-label-Iterating]
# - {Other}[#class-Dir-label-Other]
#
# === Reading
#
# - #close:: Closes the directory stream for +self+.
# - #pos=:: Sets the position in the directory stream for +self+.
# - #read:: Reads and returns the next entry in the directory stream for +self+.
# - #rewind:: Sets the position in the directory stream for +self+ to the first entry.
# - #seek:: Sets the position in the directory stream for +self+
#           the entry at the given offset.
#
# === Setting
#
# - ::chdir:: Changes the working directory of the current process
#             to the given directory.
# - ::chroot:: Changes the file-system root for the current process
#              to the given directory.
#
# === Querying
#
# - ::[]:: Same as ::glob without the ability to pass flags.
# - ::children:: Returns an array of names of the children
#                (both files and directories) of the given directory,
#                but not including <tt>.</tt> or <tt>..</tt>.
# - ::empty?:: Returns whether the given path is an empty directory.
# - ::entries:: Returns an array of names of the children
#               (both files and directories) of the given directory,
#               including <tt>.</tt> and <tt>..</tt>.
# - ::exist?:: Returns whether the given path is a directory.
# - ::getwd (aliased as #pwd):: Returns the path to the current working directory.
# - ::glob:: Returns an array of file paths matching the given pattern and flags.
# - ::home:: Returns the home directory path for a given user or the current user.
# - #children:: Returns an array of names of the children
#               (both files and directories) of +self+,
#               but not including <tt>.</tt> or <tt>..</tt>.
# - #fileno:: Returns the integer file descriptor for +self+.
# - #path (aliased as #to_path):: Returns the path used to create +self+.
# - #tell (aliased as #pos):: Returns the integer position
#                             in the directory stream for +self+.
#
# === Iterating
#
# - ::each_child:: Calls the given block with each entry in the given directory,
#                  but not including <tt>.</tt> or <tt>..</tt>.
# - ::foreach:: Calls the given block with each entryin the given directory,
#               including <tt>.</tt> and <tt>..</tt>.
# - #each:: Calls the given block with each entry in +self+,
#           including <tt>.</tt> and <tt>..</tt>.
# - #each_child:: Calls the given block with each entry in +self+,
#                 but not including <tt>.</tt> or <tt>..</tt>.
#
# === Other
#
# - ::mkdir:: Creates a directory at the given path, with optional permissions.
# - ::new:: Returns a new \Dir for the given path, with optional encoding.
# - ::open:: Same as ::new, but if a block is given, yields the \Dir to the block,
#            closing it upon block exit.
# - ::unlink (aliased as ::delete and ::rmdir):: Removes the given directory.
# - #inspect:: Returns a string description of +self+.
class Dir
  # call-seq:
  #    Dir.open( string ) -> aDir
  #    Dir.open( string, encoding: enc ) -> aDir
  #    Dir.open( string ) {| aDir | block } -> anObject
  #    Dir.open( string, encoding: enc ) {| aDir | block } -> anObject
  #
  # The optional <i>encoding</i> keyword argument specifies the encoding of the directory.
  # If not specified, the filesystem encoding is used.
  #
  # With no block, <code>open</code> is a synonym for Dir::new. If a
  # block is present, it is passed <i>aDir</i> as a parameter. The
  # directory is closed at the end of the block, and Dir::open returns
  # the value of the block.
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
  #    Dir.new( string ) -> aDir
  #    Dir.new( string, encoding: enc ) -> aDir
  #
  # Returns a new directory object for the named directory.
  #
  # The optional <i>encoding</i> keyword argument specifies the encoding of the directory.
  # If not specified, the filesystem encoding is used.
  def initialize(name, encoding: nil)
    Primitive.dir_initialize(name, encoding)
  end

  # call-seq:
  #    Dir[ string [, string ...] [, base: path] [, sort: true] ] -> array
  #
  # Equivalent to calling
  # <code>Dir.glob([</code><i>string,...</i><code>], 0)</code>.
  def self.[](*args, base: nil, sort: true)
    Primitive.dir_s_aref(args, base, sort)
  end

  # call-seq:
  #    Dir.glob( pattern, [flags], [base: path] [, sort: true] )                       -> array
  #    Dir.glob( pattern, [flags], [base: path] [, sort: true] ) { |filename| block }  -> nil
  #
  # Expands +pattern+, which is a pattern string or an Array of pattern
  # strings, and returns an array containing the matching filenames.
  # If a block is given, calls the block once for each matching filename,
  # passing the filename as a parameter to the block.
  #
  # The optional +base+ keyword argument specifies the base directory for
  # interpreting relative pathnames instead of the current working directory.
  # As the results are not prefixed with the base directory name in this
  # case, you will need to prepend the base directory name if you want real
  # paths.
  #
  # The results which matched single wildcard or character set are sorted in
  # binary ascending order, unless +false+ is given as the optional +sort+
  # keyword argument.  The order of an Array of pattern strings and braces
  # are preserved.
  #
  # Note that the pattern is not a regexp, it's closer to a shell glob.
  # See File::fnmatch for the meaning of the +flags+ parameter.
  # Case sensitivity depends on your system (+File::FNM_CASEFOLD+ is ignored).
  #
  # <code>*</code>::
  #   Matches any file. Can be restricted by other values in the glob.
  #   Equivalent to <code>/.*/mx</code> in regexp.
  #
  #   <code>*</code>::     Matches all files
  #   <code>c*</code>::    Matches all files beginning with <code>c</code>
  #   <code>*c</code>::    Matches all files ending with <code>c</code>
  #   <code>\*c\*</code>:: Match all files that have <code>c</code> in them
  #                        (including at the beginning or end).
  #
  #   Note, this will not match Unix-like hidden files (dotfiles).  In order
  #   to include those in the match results, you must use the
  #   File::FNM_DOTMATCH flag or something like <code>"{*,.*}"</code>.
  #
  # <code>**</code>::
  #   Matches directories recursively if followed by <code>/</code>.  If
  #   this path segment contains any other characters, it is the same as the
  #   usual <code>*</code>.
  #
  # <code>?</code>::
  #   Matches any one character. Equivalent to <code>/.{1}/</code> in regexp.
  #
  # <code>[set]</code>::
  #   Matches any one character in +set+.  Behaves exactly like character sets
  #   in Regexp, including set negation (<code>[^a-z]</code>).
  #
  # <code>{p,q}</code>::
  #   Matches either literal <code>p</code> or literal <code>q</code>.
  #   Equivalent to pattern alternation in regexp.
  #
  #   Matching literals may be more than one character in length.  More than
  #   two literals may be specified.
  #
  # <code>\\</code>::
  #   Escapes the next metacharacter.
  #
  #   Note that this means you cannot use backslash on windows as part of a
  #   glob, i.e.  <code>Dir["c:\\foo*"]</code> will not work, use
  #   <code>Dir["c:/foo*"]</code> instead.
  #
  # Examples:
  #
  #    Dir["config.?"]                     #=> ["config.h"]
  #    Dir.glob("config.?")                #=> ["config.h"]
  #    Dir.glob("*.[a-z][a-z]")            #=> ["main.rb"]
  #    Dir.glob("*.[^r]*")                 #=> ["config.h"]
  #    Dir.glob("*.{rb,h}")                #=> ["main.rb", "config.h"]
  #    Dir.glob("*")                       #=> ["config.h", "main.rb"]
  #    Dir.glob("*", File::FNM_DOTMATCH)   #=> [".", "config.h", "main.rb"]
  #    Dir.glob(["*.rb", "*.h"])           #=> ["main.rb", "config.h"]
  #
  #    Dir.glob("**/*.rb")                 #=> ["main.rb",
  #                                        #    "lib/song.rb",
  #                                        #    "lib/song/karaoke.rb"]
  #
  #    Dir.glob("**/*.rb", base: "lib")    #=> ["song.rb",
  #                                        #    "song/karaoke.rb"]
  #
  #    Dir.glob("**/lib")                  #=> ["lib"]
  #
  #    Dir.glob("**/lib/**/*.rb")          #=> ["lib/song.rb",
  #                                        #    "lib/song/karaoke.rb"]
  #
  #    Dir.glob("**/lib/*.rb")             #=> ["lib/song.rb"]
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
