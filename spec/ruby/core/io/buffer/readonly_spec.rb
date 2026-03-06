require_relative '../../../spec_helper'

describe "IO::Buffer#readonly?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer created with READONLY flag" do
    @buffer = IO::Buffer.new(12, IO::Buffer::INTERNAL | IO::Buffer::READONLY)
    @buffer.readonly?.should be_true
  end

  it "is true for a buffer that is non-writable" do
    @buffer = IO::Buffer.for("string")
    @buffer.readonly?.should be_true
  end

  it "is false for a modifiable buffer" do
    @buffer = IO::Buffer.new(12)
    @buffer.readonly?.should be_false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.readonly?.should be_false
  end
end
