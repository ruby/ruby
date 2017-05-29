require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#cp" do
  before :each do
    @source = tmp("source.txt")
    @copy = tmp("copied.txt")

    @contents = "This is a copy."
    File.open(@source, "w") { |f| f.write @contents }
  end

  after :each do
    File.delete @source if File.exist? @source
    File.delete @copy if File.exist? @copy
  end

  it "copies a file" do
    cp @source, @copy
    data = IO.read(@copy)
    data.should == @contents
    data.should == IO.read(@source)
  end
end

describe Object, "#touch" do
  before :all do
    @name = tmp("touched.txt")
  end

  after :each do
    File.delete @name if File.exist? @name
  end

  it "creates a file" do
    touch @name
    File.exist?(@name).should be_true
  end

  it "accepts an optional mode argument" do
    touch @name, "wb"
    File.exist?(@name).should be_true
  end

  it "overwrites an existing file" do
    File.open(@name, "w") { |f| f.puts "used" }
    File.size(@name).should > 0

    touch @name
    File.size(@name).should == 0
  end

  it "yields the open file if passed a block" do
    touch(@name) { |f| f.write "touching" }
    IO.read(@name).should == "touching"
  end
end

describe Object, "#touch" do
  before :all do
    @name = tmp("subdir/touched.txt")
  end

  after :each do
    rm_r File.dirname(@name)
  end

  it "creates all the directories in the path to the file" do
    touch @name
    File.exist?(@name).should be_true
  end
end

describe Object, "#mkdir_p" do
  before :all do
    @dir1 = tmp("/nested")
    @dir2 = @dir1 + "/directory"
    @paths = [ @dir2, @dir1 ]
  end

  after :each do
    File.delete @dir1 if File.file? @dir1
    @paths.each { |path| Dir.rmdir path if File.directory? path }
  end

  it "creates all the directories in a path" do
    mkdir_p @dir2
    File.directory?(@dir2).should be_true
  end

  it "raises an ArgumentError if a path component is a file" do
    File.open(@dir1, "w") { |f| }
    lambda { mkdir_p @dir2 }.should raise_error(ArgumentError)
  end

  it "works if multiple processes try to create the same directory concurrently" do
    original = File.method(:directory?)
    File.should_receive(:directory?).at_least(:once) { |dir|
      ret = original.call(dir)
      if !ret and dir == @dir1
        Dir.mkdir(dir) # Simulate race
      end
      ret
    }
    mkdir_p @dir1
    original.call(@dir1).should be_true
  end
end

describe Object, "#rm_r" do
  before :all do
    @topdir  = tmp("rm_r_tree")
    @topfile = @topdir + "/file.txt"
    @link    = @topdir + "/file.lnk"
    @socket  = @topdir + "/socket.sck"
    @subdir1 = @topdir + "/subdir1"
    @subdir2 = @subdir1 + "/subdir2"
    @subfile = @subdir1 + "/subfile.txt"
  end

  before :each do
    mkdir_p @subdir2
    touch @topfile
    touch @subfile
  end

  after :each do
    File.delete @link if File.exist? @link or File.symlink? @link
    File.delete @socket if File.exist? @socket
    File.delete @subfile if File.exist? @subfile
    File.delete @topfile if File.exist? @topfile

    Dir.rmdir @subdir2 if File.directory? @subdir2
    Dir.rmdir @subdir1 if File.directory? @subdir1
    Dir.rmdir @topdir if File.directory? @topdir
  end

  it "raises an ArgumentError if the path is not prefixed by MSPEC_RM_PREFIX" do
    lambda { rm_r "some_file.txt" }.should raise_error(ArgumentError)
  end

  it "removes a single file" do
    rm_r @subfile
    File.exist?(@subfile).should be_false
  end

  it "removes multiple files" do
    rm_r @topfile, @subfile
    File.exist?(@topfile).should be_false
    File.exist?(@subfile).should be_false
  end

  platform_is_not :windows do
    it "removes a symlink to a file" do
      File.symlink @topfile, @link
      rm_r @link
      File.exist?(@link).should be_false
    end

    it "removes a symlink to a directory" do
      File.symlink @subdir1, @link
      rm_r @link
      lambda do
        File.lstat(@link)
      end.should raise_error(Errno::ENOENT)
      File.exist?(@subdir1).should be_true
    end

    it "removes a dangling symlink" do
      File.symlink "non_existent_file", @link
      rm_r @link
      lambda do
        File.lstat(@link)
      end.should raise_error(Errno::ENOENT)
    end

    it "removes a socket" do
      require 'socket'
      UNIXServer.new(@socket).close
      rm_r @socket
      File.exist?(@socket).should be_false
    end
  end

  it "removes a single directory" do
    rm_r @subdir2
    File.directory?(@subdir2).should be_false
  end

  it "recursively removes a directory tree" do
    rm_r @topdir
    File.directory?(@topdir).should be_false
  end
end
