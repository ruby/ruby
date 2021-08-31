require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#eof?" do
  before :each do
    @name = tmp("empty.txt")
    touch @name
  end

  after :each do
    rm_r @name
  end

  it "returns true on an empty stream that has just been opened" do
    File.open(@name) { |empty| empty.should.eof? }
  end

  it "raises IOError on stream not opened for reading" do
    -> do
      File.open(@name, "w") { |f| f.eof? }
    end.should raise_error(IOError)
  end
end

describe "IO#eof?" do
  before :each do
    @name = fixture __FILE__, "lines.txt"
    @io = IOSpecs.io_fixture "lines.txt"
  end

  after :each do
    @io.close if @io && !@io.closed?
  end

  it "returns false when not at end of file" do
    @io.read 1
    @io.should_not.eof?
  end

  it "returns true after reading with read with no parameters" do
    @io.read()
    @io.should.eof?
  end

  it "returns true after reading with read" do
    @io.read(File.size(@name))
    @io.should.eof?
  end

  it "returns true after reading with sysread" do
    @io.sysread(File.size(@name))
    @io.should.eof?
  end

  it "returns true after reading with readlines" do
    @io.readlines
    @io.should.eof?
  end

  it "returns false on just opened non-empty stream" do
    @io.should_not.eof?
  end

  it "does not consume the data from the stream" do
    @io.should_not.eof?
    @io.getc.should == 'V'
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.eof? }.should raise_error(IOError)
  end

  it "raises IOError on stream closed for reading by close_read" do
    @io.close_read
    -> { @io.eof? }.should raise_error(IOError)
  end

  it "returns true on one-byte stream after single-byte read" do
    File.open(File.dirname(__FILE__) + '/fixtures/one_byte.txt') { |one_byte|
      one_byte.read(1)
      one_byte.should.eof?
    }
  end
end

describe "IO#eof?" do
  after :each do
    @r.close if @r && !@r.closed?
    @w.close if @w && !@w.closed?
  end

  it "returns true on receiving side of Pipe when writing side is closed" do
    @r, @w = IO.pipe
    @w.close
    @r.should.eof?
  end

  it "returns false on receiving side of Pipe when writing side wrote some data" do
    @r, @w = IO.pipe
    @w.puts "hello"
    @r.should_not.eof?
    @w.close
    @r.should_not.eof?
    @r.read
    @r.should.eof?
  end
end
