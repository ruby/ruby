require_relative '../../../spec_helper'

describe "IO::Buffer#external?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer with externally-managed memory" do
    @buffer = IO::Buffer.for("string")
    @buffer.external?.should == true
  end

  it "is false for a buffer with self-managed memory" do
    @buffer = IO::Buffer.new(12, IO::Buffer::MAPPED)
    @buffer.external?.should == false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.external?.should == false
  end
end
