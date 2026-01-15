require_relative '../../spec_helper'
require_relative 'shared/open'

describe "File.new" do
  before :each do
    @file = tmp('test.txt')
    @fh = nil
    @flags = File::CREAT | File::TRUNC | File::WRONLY
    touch @file
  end

  after :each do
    @fh.close if @fh
    rm_r @file
  end

  it "returns a new File with mode string" do
    @fh = File.new(@file, 'w')
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new File with mode num" do
    @fh = File.new(@file, @flags)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new File with modus num and permissions" do
    rm_r @file
    File.umask(0011)
    @fh = File.new(@file, @flags, 0755)
    @fh.should be_kind_of(File)
    platform_is_not :windows do
      File.stat(@file).mode.to_s(8).should == "100744"
    end
    File.should.exist?(@file)
  end

  it "creates the file and returns writable descriptor when called with 'w' mode and r-o permissions" do
    # it should be possible to write to such a file via returned descriptor,
    # even though the file permissions are r-r-r.

    rm_r @file
    begin
      f = File.new(@file, "w", 0444)
      -> { f.puts("test") }.should_not raise_error(IOError)
    ensure
      f.close
    end
    File.should.exist?(@file)
    File.read(@file).should == "test\n"
  end

  platform_is_not :windows do
    it "opens the existing file, does not change permissions even when they are specified" do
      File.chmod(0644, @file)           # r-w perms
      orig_perms = File.stat(@file).mode & 0777
      begin
        f = File.new(@file, "w", 0444)    # r-o perms, but they should be ignored
        f.puts("test")
      ensure
        f.close
      end
      perms = File.stat(@file).mode & 0777
      perms.should == orig_perms

      # it should be still possible to read from the file
      File.read(@file).should == "test\n"
    end
  end

  it "returns a new File with modus fd" do
    @fh = File.new(@file)
    fh_copy = File.new(@fh.fileno)
    fh_copy.autoclose = false
    fh_copy.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new read-only File when mode is not specified" do
    @fh = File.new(@file)

    -> { @fh.puts("test") }.should raise_error(IOError)
    @fh.read.should == ""
    File.should.exist?(@file)
  end

  it "returns a new read-only File when mode is not specified but flags option is present" do
    @fh = File.new(@file, flags: File::CREAT)

    -> { @fh.puts("test") }.should raise_error(IOError)
    @fh.read.should == ""
    File.should.exist?(@file)
  end

  it "creates a new file when use File::EXCL mode" do
    @fh = File.new(@file, File::EXCL)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "raises an Errno::EEXIST if the file exists when create a new file with File::CREAT|File::EXCL" do
    -> { @fh = File.new(@file, File::CREAT|File::EXCL) }.should raise_error(Errno::EEXIST)
  end

  it "creates a new file when use File::WRONLY|File::APPEND mode" do
    @fh = File.new(@file, File::WRONLY|File::APPEND)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new File when use File::APPEND mode" do
    @fh = File.new(@file, File::APPEND)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new File when use File::RDONLY|File::APPEND mode" do
    @fh = File.new(@file, File::RDONLY|File::APPEND)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new File when use File::RDONLY|File::WRONLY mode" do
    @fh = File.new(@file, File::RDONLY|File::WRONLY)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "creates a new file when use File::WRONLY|File::TRUNC mode" do
    @fh = File.new(@file, File::WRONLY|File::TRUNC)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)
  end

  it "returns a new read-only File when use File::RDONLY|File::CREAT mode" do
    @fh = File.new(@file, File::RDONLY|File::CREAT)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)

    # it's read-only
    -> { @fh.puts("test") }.should raise_error(IOError)
    @fh.read.should == ""
  end

  it "returns a new read-only File when use File::CREAT mode" do
    @fh = File.new(@file, File::CREAT)
    @fh.should be_kind_of(File)
    File.should.exist?(@file)

    # it's read-only
    -> { @fh.puts("test") }.should raise_error(IOError)
    @fh.read.should == ""
  end

  it "coerces filename using to_str" do
    name = mock("file")
    name.should_receive(:to_str).and_return(@file)
    @fh = File.new(name, "w")
    File.should.exist?(@file)
  end

  it "coerces filename using #to_path" do
    name = mock("file")
    name.should_receive(:to_path).and_return(@file)
    @fh = File.new(name, "w")
    File.should.exist?(@file)
  end

  it "accepts options as a keyword argument" do
    @fh = File.new(@file, 'w', 0755, flags: @flags)
    @fh.should be_kind_of(File)
    @fh.close

    -> {
      @fh = File.new(@file, 'w', 0755, {flags: @flags})
    }.should raise_error(ArgumentError, "wrong number of arguments (given 4, expected 1..3)")
  end

  it "bitwise-ORs mode and flags option" do
    -> {
      @fh = File.new(@file, 'w', flags: File::EXCL)
    }.should raise_error(Errno::EEXIST, /File exists/)

    -> {
      @fh = File.new(@file, mode: 'w', flags: File::EXCL)
    }.should raise_error(Errno::EEXIST, /File exists/)
  end

  it "does not use the given block and warns to use File::open" do
    -> {
      @fh = File.new(@file) { raise }
    }.should complain(/warning: File::new\(\) does not take block; use File::open\(\) instead/)
  end

  it "raises a TypeError if the first parameter can't be coerced to a string" do
    -> { File.new(true) }.should raise_error(TypeError)
    -> { File.new(false) }.should raise_error(TypeError)
  end

  it "raises a TypeError if the first parameter is nil" do
    -> { File.new(nil) }.should raise_error(TypeError)
  end

  it "raises an Errno::EBADF if the first parameter is an invalid file descriptor" do
    -> { File.new(-1) }.should raise_error(Errno::EBADF)
  end

  platform_is_not :windows do
    it "can't alter mode or permissions when opening a file" do
      @fh = File.new(@file)
      -> {
        f = File.new(@fh.fileno, @flags)
        f.autoclose = false
      }.should raise_error(Errno::EINVAL)
    end
  end

  platform_is_not :windows do
    it_behaves_like :open_directory, :new
  end
end
