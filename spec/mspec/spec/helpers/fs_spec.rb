require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe Object, "#cp" do
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
    expect(data).to eq(@contents)
    expect(data).to eq(IO.read(@source))
  end
end

RSpec.describe Object, "#touch" do
  before :all do
    @name = tmp("touched.txt")
  end

  after :each do
    File.delete @name if File.exist? @name
  end

  it "creates a file" do
    touch @name
    expect(File.exist?(@name)).to be_truthy
  end

  it "accepts an optional mode argument" do
    touch @name, "wb"
    expect(File.exist?(@name)).to be_truthy
  end

  it "overwrites an existing file" do
    File.open(@name, "w") { |f| f.puts "used" }
    expect(File.size(@name)).to be > 0

    touch @name
    expect(File.size(@name)).to eq(0)
  end

  it "yields the open file if passed a block" do
    touch(@name) { |f| f.write "touching" }
    expect(IO.read(@name)).to eq("touching")
  end
end

RSpec.describe Object, "#touch" do
  before :all do
    @name = tmp("subdir/touched.txt")
  end

  after :each do
    rm_r File.dirname(@name)
  end

  it "creates all the directories in the path to the file" do
    touch @name
    expect(File.exist?(@name)).to be_truthy
  end
end

RSpec.describe Object, "#mkdir_p" do
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
    expect(File.directory?(@dir2)).to be_truthy
  end

  it "raises an ArgumentError if a path component is a file" do
    File.open(@dir1, "w") { |f| }
    expect { mkdir_p @dir2 }.to raise_error(ArgumentError)
  end

  it "works if multiple processes try to create the same directory concurrently" do
    original = File.method(:directory?)
    expect(File).to receive(:directory?).at_least(:once) { |dir|
      ret = original.call(dir)
      if !ret and dir == @dir1
        Dir.mkdir(dir) # Simulate race
      end
      ret
    }
    mkdir_p @dir1
    expect(original.call(@dir1)).to be_truthy
  end
end

RSpec.describe Object, "#rm_r" do
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
    expect { rm_r "some_file.txt" }.to raise_error(ArgumentError)
  end

  it "removes a single file" do
    rm_r @subfile
    expect(File.exist?(@subfile)).to be_falsey
  end

  it "removes multiple files" do
    rm_r @topfile, @subfile
    expect(File.exist?(@topfile)).to be_falsey
    expect(File.exist?(@subfile)).to be_falsey
  end

  platform_is_not :windows do
    it "removes a symlink to a file" do
      File.symlink @topfile, @link
      rm_r @link
      expect(File.exist?(@link)).to be_falsey
    end

    it "removes a symlink to a directory" do
      File.symlink @subdir1, @link
      rm_r @link
      expect do
        File.lstat(@link)
      end.to raise_error(Errno::ENOENT)
      expect(File.exist?(@subdir1)).to be_truthy
    end

    it "removes a dangling symlink" do
      File.symlink "non_existent_file", @link
      rm_r @link
      expect do
        File.lstat(@link)
      end.to raise_error(Errno::ENOENT)
    end

    it "removes a socket" do
      require 'socket'
      UNIXServer.new(@socket).close
      rm_r @socket
      expect(File.exist?(@socket)).to be_falsey
    end
  end

  it "removes a single directory" do
    rm_r @subdir2
    expect(File.directory?(@subdir2)).to be_falsey
  end

  it "recursively removes a directory tree" do
    rm_r @topdir
    expect(File.directory?(@topdir)).to be_falsey
  end
end
