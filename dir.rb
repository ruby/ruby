class Dir
  #
  #  call-seq:
  #     Dir.new( string ) -> aDir
  #     Dir.new( string, encoding: enc ) -> aDir
  #
  #  Returns a new directory object for the named directory.
  #
  #  The optional <i>encoding</i> keyword argument specifies the encoding of the directory.
  #  If not specified, the filesystem encoding is used.
  #
  def initialize(path, encoding: Encoding.find("filesystem"))
    __builtin_dir_initialize(path, encoding)
  end

  #
  #  call-seq:
  #     Dir.open( string ) -> aDir
  #     Dir.open( string, encoding: enc ) -> aDir
  #     Dir.open( string ) {| aDir | block } -> anObject
  #     Dir.open( string, encoding: enc ) {| aDir | block } -> anObject
  #
  #  The optional <i>encoding</i> keyword argument specifies the encoding of the directory.
  #  If not specified, the filesystem encoding is used.
  #
  #  With no block, <code>open</code> is a synonym for Dir::new. If a
  #  block is present, it is passed <i>aDir</i> as a parameter. The
  #  directory is closed at the end of the block, and Dir::open returns
  #  the value of the block.
  #
  def self.open(path, encoding: Encoding.find("filesystem"))
    __builtin_dir_s_open(path, encoding)
  end

  #
  #  call-seq:
  #     Dir.foreach( dirname ) {| filename | block }                 -> nil
  #     Dir.foreach( dirname, encoding: enc ) {| filename | block }  -> nil
  #     Dir.foreach( dirname )                                       -> an_enumerator
  #     Dir.foreach( dirname, encoding: enc )                        -> an_enumerator
  #
  #  Calls the block once for each entry in the named directory, passing
  #  the filename of each entry as a parameter to the block.
  #
  #  If no block is given, an enumerator is returned instead.
  #
  #     Dir.foreach("testdir") {|x| puts "Got #{x}" }
  #
  #  <em>produces:</em>
  #
  #     Got .
  #     Got ..
  #     Got config.h
  #     Got main.rb
  #
  #
  def self.foreach(path, encoding: Encoding.find("filesystem"))
    return Enumerator.new(Dir.new(path, encoding: encoding)) if !block_given?
    __builtin_dir_foreach(path, encoding)
  end

  #
  #  call-seq:
  #     Dir.entries( dirname )                -> array
  #     Dir.entries( dirname, encoding: enc ) -> array
  #
  #  Returns an array containing all of the filenames in the given
  #  directory. Will raise a SystemCallError if the named directory
  #  doesn't exist.
  #
  #  The optional <i>encoding</i> keyword argument specifies the encoding of the
  #  directory. If not specified, the filesystem encoding is used.
  #
  #     Dir.entries("testdir")   #=> [".", "..", "config.h", "main.rb"]
  #
  #
  def self.entries(path, encoding: Encoding.find("filesystem"))
    __builtin_dir_entries(path, encoding)
  end

  #
  #  call-seq:
  #     Dir.each_child( dirname ) {| filename | block }                 -> nil
  #     Dir.each_child( dirname, encoding: enc ) {| filename | block }  -> nil
  #     Dir.each_child( dirname )                                       -> an_enumerator
  #     Dir.each_child( dirname, encoding: enc )                        -> an_enumerator
  #
  #  Calls the block once for each entry except for "." and ".." in the
  #  named directory, passing the filename of each entry as a parameter
  #  to the block.
  #
  #  If no block is given, an enumerator is returned instead.
  #
  #     Dir.each_child("testdir") {|x| puts "Got #{x}" }
  #
  #  <em>produces:</em>
  #
  #     Got config.h
  #     Got main.rb
  #
  #
  def self.each_child(path, encoding: Encoding.find("filesystem"))
    return Enumerator.new(Dir.children(path, encoding: encoding)) if !block_given?
    __builtin_dir_s_each_child(path, encoding)
  end

  #
  #  call-seq:
  #     Dir.children( dirname )                -> array
  #     Dir.children( dirname, encoding: enc ) -> array
  #
  #  Returns an array containing all of the filenames except for "."
  #  and ".." in the given directory. Will raise a SystemCallError if
  #  the named directory doesn't exist.
  #
  #  The optional <i>encoding</i> keyword argument specifies the encoding of the
  #  directory. If not specified, the filesystem encoding is used.
  #
  #     Dir.children("testdir")   #=> ["config.h", "main.rb"]
  #
  #
  def self.children(path, encoding: Encoding.find("filesystem"))
    __builtin_dir_s_children(path, encoding)
  end
end
