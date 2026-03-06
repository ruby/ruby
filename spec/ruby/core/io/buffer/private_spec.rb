require_relative '../../../spec_helper'

describe "IO::Buffer#private?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer created with PRIVATE flag" do
    @buffer = IO::Buffer.new(12, IO::Buffer::INTERNAL | IO::Buffer::PRIVATE)
    @buffer.private?.should be_true
  end

  it "is false for a buffer created without PRIVATE flag" do
    @buffer = IO::Buffer.new(12, IO::Buffer::INTERNAL)
    @buffer.private?.should be_false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.private?.should be_false
  end
end
