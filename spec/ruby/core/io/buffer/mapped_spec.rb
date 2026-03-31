require_relative '../../../spec_helper'

describe "IO::Buffer#mapped?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer with mapped memory" do
    @buffer = IO::Buffer.new(12, IO::Buffer::MAPPED)
    @buffer.mapped?.should be_true
  end

  it "is false for a buffer with non-mapped memory" do
    @buffer = IO::Buffer.for("string")
    @buffer.mapped?.should be_false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.mapped?.should be_false
  end
end
