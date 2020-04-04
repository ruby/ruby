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
end
