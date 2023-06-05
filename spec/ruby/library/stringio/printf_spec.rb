require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../core/kernel/shared/sprintf'

describe "StringIO#printf" do
  before :each do
    @io = StringIO.new()
  end

  it "returns nil" do
    @io.printf("%d %04x", 123, 123).should be_nil
  end

  it "pads self with \\000 when the current position is after the end" do
    @io.pos = 3
    @io.printf("%d", 123)
    @io.string.should == "\000\000\000123"
  end

  it "performs format conversion" do
    @io.printf("%d %04x", 123, 123)
    @io.string.should == "123 007b"
  end

  it "updates the current position" do
    @io.printf("%d %04x", 123, 123)
    @io.pos.should eql(8)

    @io.printf("%d %04x", 123, 123)
    @io.pos.should eql(16)
  end

  describe "formatting" do
    it_behaves_like :kernel_sprintf, -> format, *args {
      io = StringIO.new(+"")
      io.printf(format, *args)
      io.string
    }
  end
end

describe "StringIO#printf when in read-write mode" do
  before :each do
    @io = StringIO.new("example", "r+")
  end

  it "starts from the beginning" do
    @io.printf("%s", "abcdefghijk")
    @io.string.should == "abcdefghijk"
  end

  it "does not truncate existing string" do
    @io.printf("%s", "abc")
    @io.string.should == "abcmple"
  end

  it "correctly updates self's position" do
    @io.printf("%s", "abc")
    @io.pos.should eql(3)
  end
end

describe "StringIO#printf when in append mode" do
  before :each do
    @io = StringIO.new("example", "a")
  end

  it "appends the passed argument to the end of self" do
    @io.printf("%d %04x", 123, 123)
    @io.string.should == "example123 007b"

    @io.printf("%d %04x", 123, 123)
    @io.string.should == "example123 007b123 007b"
  end

  it "correctly updates self's position" do
    @io.printf("%d %04x", 123, 123)
    @io.pos.should eql(15)
  end
end

describe "StringIO#printf when self is not writable" do
  it "raises an IOError" do
    io = StringIO.new("test", "r")
    -> { io.printf("test") }.should raise_error(IOError)

    io = StringIO.new("test")
    io.close_write
    -> { io.printf("test") }.should raise_error(IOError)
  end
end
