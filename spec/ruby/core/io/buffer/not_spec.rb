require_relative '../../../spec_helper'

describe :io_buffer_not, shared: true do
  it "inverts every bit of the buffer" do
    IO::Buffer.for(+"12345") do |buffer|
      result = buffer.send(@method)
      result.get_string.should == "\xCE\xCD\xCC\xCB\xCA".b
      result.free
    end
  end
end

describe "IO::Buffer#~" do
  it_behaves_like :io_buffer_not, :~

  it "creates a new internal buffer of the same size" do
    IO::Buffer.for(+"12345") do |buffer|
      result = ~buffer
      result.should_not.equal? buffer
      result.should.internal?
      result.size.should == buffer.size
      result.free
    end
  end
end

describe "IO::Buffer#not!" do
  it_behaves_like :io_buffer_not, :not!

  it "modifies the buffer in place" do
    IO::Buffer.for(+"12345") do |buffer|
      result = buffer.not!
      result.should.equal? buffer
      result.should.external?
    end
  end
end
