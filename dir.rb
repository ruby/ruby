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
# - It includes {module Enumerable}[rdoc-ref:Enumerable@Whats+Here].
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
# - Method #tell (aliased as #pos) returns the position.
# - Method #pos= sets the position (but ignores a value outside the stream),
#   and returns the position.
# - Method #seek is like #pos=, but returns +self+ (convenient for chaining).
# - Method #read, if not at end-of-stream, reads the next entry and increments
#   the position;
#   if at end-of-stream, does not increment the position.
# - Method #rewind sets the position to zero.
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
# First, what's elsewhere. Class \Dir:
#
# - Inherits from {class Object}[rdoc-ref:Object@Whats+Here].
# - Includes {module Enumerable}[rdoc-ref:Enumerable@Whats+Here],
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
  #   Dir.open('.', encoding: Encoding::US_ASCII).read.encoding # => #<Encoding:US-ASCII>
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
  #   Dir.new('.', encoding: Encoding::US_ASCI).read.encoding # => #<Encoding:US-ASCII>
  #
  def initialize(name, encoding: nil)
    Primitive.dir_initialize(name, encoding)
  end

  # call-seq:
  #   Dir[*patterns, base: nil, sort: true] -> array
  #
  # Like Dir.glob, but does not accept keyword argument +flags+,
  # and may take multiple patterns as arguments:
  #
  #   Dir['*.rb', '*.h'].take(3) # => ["KNOWNBUGS.rb", "array.rb", "ast.rb"]
  #
  def self.[](*args, base: nil, sort: true)
    Primitive.dir_s_aref(args, base, sort)
  end

  # call-seq:
  #   Dir.glob(patterns, flags: 0, base: '.', sort: true) -> array_of_entries
  #   Dir.glob(patterns, flags: 0, base: '.', sort: true) {|entry_name| ... } -> nil
  #
  # Returns an array of filesystem entries;
  # see {Filename Globbing}[rdoc-ref:file/filename_globbing.md].
  #
  # With a block given, calls the block with each of the selected entry names
  # and returns +nil+:
  #
  #   Dir.glob('*.rb') {|entry_name| puts entry_name } # => nil
  #
  def self.glob(pattern, _flags = 0, flags: _flags, base: nil, sort: true)
    Primitive.attr! :use_block
    Primitive.dir_s_glob(pattern, flags, base, sort)
  end
end

class << File

  # :markup: markdown
  #
  # call-seq:
  #   File.fnmatch(pattern, path, flags = 0) -> true or false
  #
  # Returns whether string `pattern` matches against string `path`,
  # under the control of the given `flags`;
  # see [Filename Matching](rdoc-ref:file/filename_matching.md).
  def fnmatch(pattern, path, flags = 0)
  end
  alias fnmatch? fnmatch
end if false
