require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#sysread on a file" do
  before :each do
    @file_name = tmp("IO_sysread_file") + $$.to_s
    File.open(@file_name, "w") do |f|
      # write some stuff
      f.write("012345678901234567890123456789\nabcdef")
    end
    @file = File.open(@file_name, "r+")
  end

  after :each do
    @file.close
    rm_r @file_name
  end

  it "reads the specified number of bytes from the file" do
    @file.sysread(15).should == "012345678901234"
  end

  it "reads the specified number of bytes from the file to the buffer" do
    buf = +"" # empty buffer
    @file.sysread(15, buf).should == buf
    buf.should == "012345678901234"

    @file.rewind

    buf = +"ABCDE" # small buffer
    @file.sysread(15, buf).should == buf
    buf.should == "012345678901234"

    @file.rewind

    buf = +"ABCDE" * 5 # large buffer
    @file.sysread(15, buf).should == buf
    buf.should == "012345678901234"
  end

  it "coerces the second argument to string and uses it as a buffer" do
    buf = +"ABCDE"
    (obj = mock("buff")).should_receive(:to_str).any_number_of_times.and_return(buf)
    @file.sysread(15, obj).should == buf
    buf.should == "012345678901234"
  end

  it "advances the position of the file by the specified number of bytes" do
    @file.sysread(15)
    @file.sysread(5).should == "56789"
  end

  it "raises an error when called after buffered reads" do
    @file.readline
    -> { @file.sysread(5) }.should raise_error(IOError)
  end

  it "reads normally even when called immediately after a buffered IO#read" do
    @file.read(15)
    @file.sysread(5).should == "56789"
  end

  it "does not raise error if called after IO#read followed by IO#write" do
    @file.read(5)
    @file.write("abcde")
    -> { @file.sysread(5) }.should_not raise_error(IOError)
  end

  it "does not raise error if called after IO#read followed by IO#syswrite" do
    @file.read(5)
    @file.syswrite("abcde")
    -> { @file.sysread(5) }.should_not raise_error(IOError)
  end

  it "reads updated content after the flushed buffered IO#write" do
    @file.write("abcde")
    @file.flush
    @file.sysread(5).should == "56789"
    File.open(@file_name) do |f|
      f.sysread(10).should == "abcde56789"
    end
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.sysread(5) }.should raise_error(IOError)
  end

  it "immediately returns an empty string if the length argument is 0" do
    @file.sysread(0).should == ""
  end

  it "immediately returns the given buffer if the length argument is 0" do
    buffer = +"existing content"
    @file.sysread(0, buffer).should == buffer
    buffer.should == "existing content"
  end

  it "discards the existing buffer content upon successful read" do
    buffer = +"existing content"
    @file.sysread(11, buffer).should.equal?(buffer)
    buffer.should == "01234567890"
  end

  it "discards the existing buffer content upon error" do
    buffer = +"existing content"
    @file.seek(0, :END)
    -> { @file.sysread(1, buffer) }.should raise_error(EOFError)
    buffer.should be_empty
  end

  it "preserves the encoding of the given buffer" do
    buffer = ''.encode(Encoding::ISO_8859_1)
    string = @file.sysread(10, buffer)

    buffer.encoding.should == Encoding::ISO_8859_1
  end
end

describe "IO#sysread" do
  before do
    @read, @write = IO.pipe
  end

  after do
    @read.close
    @write.close
  end

  it "returns a smaller string if less than size bytes are available" do
    @write.syswrite "ab"
    @read.sysread(3).should == "ab"
  end

  guard_not -> { platform_is :windows and ruby_version_is ""..."3.2" } do # https://bugs.ruby-lang.org/issues/18880
    it "raises ArgumentError when length is less than 0" do
      -> { @read.sysread(-1) }.should raise_error(ArgumentError)
    end
  end
end
