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
    dir = __builtin_dir_s_open(name, encoding)
    if block
      begin
        yield dir
      ensure
        __builtin_dir_s_close(dir)
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
    __builtin_dir_initialize(name, encoding)
  end
end
