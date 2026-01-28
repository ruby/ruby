require_relative '../../../spec_helper'

describe "IO::Buffer#internal?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for an internally-allocated buffer" do
    @buffer = IO::Buffer.new(12)
    @buffer.internal?.should be_true
  end

  it "is false for an externally-allocated buffer" do
    @buffer = IO::Buffer.new(12, IO::Buffer::MAPPED)
    @buffer.internal?.should be_false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.internal?.should be_false
  end
end
