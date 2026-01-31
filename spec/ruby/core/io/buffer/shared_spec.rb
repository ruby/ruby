require_relative '../../../spec_helper'

describe "IO::Buffer#shared?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer created with SHARED flag" do
    @buffer = IO::Buffer.new(12, IO::Buffer::INTERNAL | IO::Buffer::SHARED)
    @buffer.shared?.should be_true
  end

  it "is true for a non-private buffer created with .map" do
    path = tmp("read_text.txt")
    File.copy_stream(fixture(__dir__, "read_text.txt"), path)
    file = File.open(path, "r+")
    @buffer = IO::Buffer.map(file)
    @buffer.shared?.should be_true
  ensure
    @buffer.free
    file.close
    File.unlink(path)
  end

  it "is false for an unshared buffer" do
    @buffer = IO::Buffer.new(12)
    @buffer.shared?.should be_false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.shared?.should be_false
  end
end
