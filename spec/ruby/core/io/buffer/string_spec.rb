require_relative '../../../spec_helper'

describe "IO::Buffer.string" do
  it "creates a modifiable buffer for the duration of the block" do
    IO::Buffer.string(7) do |buffer|
      @buffer = buffer

      buffer.size.should == 7
      buffer.get_string.should == "\0\0\0\0\0\0\0".b

      buffer.set_string("test")
      buffer.get_string.should == "test\0\0\0"
    end
    @buffer.should.null?
  end

  it "returns contents of the buffer as a binary string" do
    string =
      IO::Buffer.string(7) do |buffer|
        buffer.set_string("ä test")
      end
    string.should == "\xC3\xA4 test".b
  end

  it "creates an external buffer" do
    IO::Buffer.string(8) do |buffer|
      buffer.should_not.internal?
      buffer.should_not.mapped?
      buffer.should.external?

      buffer.should_not.empty?
      buffer.should_not.null?

      buffer.should_not.shared?
      buffer.should_not.private?
      buffer.should_not.readonly?

      buffer.should_not.locked?
      buffer.should.valid?
    end
  end

  it "returns an empty string if size is 0" do
    string =
      IO::Buffer.string(0) do |buffer|
        buffer.size.should == 0
      end
    string.should == ""
  end

  it "raises ArgumentError if size is negative" do
    -> { IO::Buffer.string(-1) {} }.should raise_error(ArgumentError, "negative string size (or size too big)")
  end

  it "raises RangeError if size is too large" do
    -> { IO::Buffer.string(2 ** 232) {} }.should raise_error(RangeError, /\Abignum too big to convert into [`']long'\z/)
  end

  it "raises LocalJumpError if no block is given" do
    -> { IO::Buffer.string(7) }.should raise_error(LocalJumpError, "no block given")
  end
end
