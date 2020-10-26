class Dir
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

  #    Dir[ string [, string ...] [, base: path] [, sort: true] ] -> array
  #
  # Equivalent to calling
  # <code>Dir.glob([</code><i>string,...</i><code>], 0)</code>.
  def self.[](*args, base: nil, sort: true)
    Primitive.dir_s_aref(args, base, sort)
  end

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
  # binary ascending order, unless false is given as the optional +sort+
  # keyword argument.  The order of an Array of pattern strings and braces
  # are preserved.
  #
  # Note that the pattern is not a regexp, it's closer to a shell glob.
  # See File::fnmatch for the meaning of the +flags+ parameter.
  # Case sensitivity depends on your system (File::FNM_CASEFOLD is ignored).
  #
  # <code>*</code>::
  #   Matches any file. Can be restricted by other values in the glob.
  #   Equivalent to <code>/ .* /mx</code> in regexp.
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
  # <code> \\ </code>::
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
  #    Dir.glob("*", File::FNM_DOTMATCH)   #=> [".", "..", "config.h", "main.rb"]
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
