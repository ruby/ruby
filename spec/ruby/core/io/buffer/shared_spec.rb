require_relative '../../../spec_helper'

describe "IO::Buffer#shared?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer created with SHARED flag" do
    @buffer = IO::Buffer.new(12, IO::Buffer::INTERNAL | IO::Buffer::SHARED)
    @buffer.shared?.should == true
  end

  it "is true for a non-private buffer created with .map" do
    path = fixture(__dir__, "read_text.txt")
    file = File.open(path, "r+")
    @buffer = IO::Buffer.map(file)
    @buffer.shared?.should == true
  ensure
    @buffer.free
    file.close
  end

  it "is false for an unshared buffer" do
    @buffer = IO::Buffer.new(12)
    @buffer.shared?.should == false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.shared?.should == false
  end
end
