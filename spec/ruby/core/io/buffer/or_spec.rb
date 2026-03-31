require_relative '../../../spec_helper'

describe :io_buffer_or, shared: true do
  it "applies the argument buffer as an OR bit mask across the whole buffer" do
    IO::Buffer.for(+"12345") do |buffer|
      IO::Buffer.for(+"\xF8\x8F") do |mask|
        result = buffer.send(@method, mask)
        result.get_string.should == "\xF9\xBF\xFB\xBF\xFD".b
        result.free
      end
    end
  end

  it "ignores extra parts of mask if it is longer than source buffer" do
    IO::Buffer.for(+"12345") do |buffer|
      IO::Buffer.for(+"\xF8\x8F\x00\x00\x00\xFF\xFF") do |mask|
        result = buffer.send(@method, mask)
        result.get_string.should == "\xF9\xBF345".b
        result.free
      end
    end
  end

  it "raises TypeError if mask is not an IO::Buffer" do
    IO::Buffer.for(+"12345") do |buffer|
      -> { buffer.send(@method, "\xF8\x8F") }.should raise_error(TypeError, "wrong argument type String (expected IO::Buffer)")
      -> { buffer.send(@method, 0xF8) }.should raise_error(TypeError, "wrong argument type Integer (expected IO::Buffer)")
      -> { buffer.send(@method, nil) }.should raise_error(TypeError, "wrong argument type nil (expected IO::Buffer)")
    end
  end
end

describe "IO::Buffer#|" do
  it_behaves_like :io_buffer_or, :|

  it "creates a new internal buffer of the same size" do
    IO::Buffer.for(+"12345") do |buffer|
      IO::Buffer.for(+"\xF8\x8F") do |mask|
        result = buffer | mask
        result.should_not.equal? buffer
        result.should.internal?
        result.size.should == buffer.size
        result.free
        buffer.get_string.should == "12345".b
      end
    end
  end
end

describe "IO::Buffer#or!" do
  it_behaves_like :io_buffer_or, :or!

  it "modifies the buffer in place" do
    IO::Buffer.for(+"12345") do |buffer|
      IO::Buffer.for(+"\xF8\x8F") do |mask|
        result = buffer.or!(mask)
        result.should.equal? buffer
        result.should.external?
      end
    end
  end
end
