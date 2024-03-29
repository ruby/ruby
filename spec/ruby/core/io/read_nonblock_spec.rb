require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#read_nonblock" do
  before :each do
    @read, @write = IO.pipe
  end

  after :each do
    @read.close if @read && !@read.closed?
    @write.close if @write && !@write.closed?
  end

  it "raises an exception extending IO::WaitReadable when there is no data" do
    -> { @read.read_nonblock(5) }.should raise_error(IO::WaitReadable) { |e|
      platform_is_not :windows do
        e.should be_kind_of(Errno::EAGAIN)
      end
      platform_is :windows do
        e.should be_kind_of(Errno::EWOULDBLOCK)
      end
    }
  end

  context "when exception option is set to false" do
    context "when there is no data" do
      it "returns :wait_readable" do
        @read.read_nonblock(5, exception: false).should == :wait_readable
      end
    end

    context "when the end is reached" do
      it "returns nil" do
        @write << "hello"
        @write.close

        @read.read_nonblock(5)

        @read.read_nonblock(5, exception: false).should be_nil
      end
    end
  end

  platform_is_not :windows do
    it 'sets the IO in nonblock mode' do
      require 'io/nonblock'
      @write.write "abc"
      @read.read_nonblock(1).should == "a"
      @read.should.nonblock?
    end
  end

  it "returns at most the number of bytes requested" do
    @write << "hello"
    @read.read_nonblock(4).should == "hell"
  end

  it "reads after ungetc with data in the buffer" do
    @write.write("foobar")
    @read.set_encoding(
      'utf-8', universal_newline: false
    )
    c = @read.getc
    @read.ungetc(c)
    @read.read_nonblock(3).should == "foo"
    @read.read_nonblock(3).should == "bar"
  end

  it "raises an exception after ungetc with data in the buffer and character conversion enabled" do
    @write.write("foobar")
    @read.set_encoding(
      'utf-8', universal_newline: true
    )
    c = @read.getc
    @read.ungetc(c)
    -> { @read.read_nonblock(3).should == "foo" }.should raise_error(IOError)
  end

  it "returns less data if that is all that is available" do
    @write << "hello"
    @read.read_nonblock(10).should == "hello"
  end

  it "allows for reading 0 bytes before any write" do
    @read.read_nonblock(0).should == ""
  end

  it "allows for reading 0 bytes after a write" do
    @write.write "1"
    @read.read_nonblock(0).should == ""
    @read.read_nonblock(1).should == "1"
  end

  it "raises ArgumentError when length is less than 0" do
    -> { @read.read_nonblock(-1) }.should raise_error(ArgumentError)
  end

  it "reads into the passed buffer" do
    buffer = +""
    @write.write("1")
    @read.read_nonblock(1, buffer)
    buffer.should == "1"
  end

  it "returns the passed buffer" do
    buffer = +""
    @write.write("1")
    output = @read.read_nonblock(1, buffer)
    output.should equal(buffer)
  end

  it "discards the existing buffer content upon successful read" do
    buffer = +"existing content"
    @write.write("hello world")
    @write.close
    @read.read_nonblock(11, buffer)
    buffer.should == "hello world"
  end

  it "discards the existing buffer content upon error" do
    buffer = +"existing content"
    @write.close
    -> { @read.read_nonblock(1, buffer) }.should raise_error(EOFError)
    buffer.should be_empty
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.read_nonblock(5) }.should raise_error(IOError)
  end

  it "raises EOFError when the end is reached" do
    @write << "hello"
    @write.close

    @read.read_nonblock(5)

    -> { @read.read_nonblock(5) }.should raise_error(EOFError)
  end

  it "preserves the encoding of the given buffer" do
    buffer = ''.encode(Encoding::ISO_8859_1)
    @write.write("abc")
    @write.close
    @read.read_nonblock(10, buffer)

    buffer.encoding.should == Encoding::ISO_8859_1
  end
end
