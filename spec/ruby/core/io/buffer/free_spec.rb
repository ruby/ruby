require_relative '../../../spec_helper'

describe "IO::Buffer#free" do
  context "with a buffer created with .new" do
    it "frees internal memory and nullifies the buffer" do
      buffer = IO::Buffer.new(4)
      buffer.free
      buffer.null?.should be_true
    end

    it "frees mapped memory and nullifies the buffer" do
      buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
      buffer.free
      buffer.null?.should be_true
    end
  end

  context "with a file-backed buffer created with .map" do
    it "frees mapped memory and nullifies the buffer" do
      File.open(__FILE__, "r") do |file|
        buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        buffer.free
        buffer.null?.should be_true
      end
    end
  end

  context "with a String-backed buffer created with .for" do
    context "without a block" do
      it "disassociates the buffer from the string and nullifies the buffer" do
        string = +"test"
        buffer = IO::Buffer.for(string)
        # Read-only buffer, can't modify the string.
        buffer.free
        buffer.null?.should be_true
      end
    end

    context "with a block" do
      it "disassociates the buffer from the string and nullifies the buffer" do
        string = +"test"
        IO::Buffer.for(string) do |buffer|
          buffer.set_string("meat")
          buffer.free
          buffer.null?.should be_true
        end
        string.should == "meat"
      end
    end
  end

  ruby_version_is "3.3" do
    context "with a String-backed buffer created with .string" do
      it "disassociates the buffer from the string and nullifies the buffer" do
        string =
          IO::Buffer.string(4) do |buffer|
            buffer.set_string("meat")
            buffer.free
            buffer.null?.should be_true
          end
        string.should == "meat"
      end
    end
  end

  it "can be called repeatedly without an error" do
    buffer = IO::Buffer.new(4)
    buffer.free
    buffer.null?.should be_true
    buffer.free
    buffer.null?.should be_true
  end

  it "is disallowed while locked, raising IO::Buffer::LockedError" do
    buffer = IO::Buffer.new(4)
    buffer.locked do
      -> { buffer.free }.should raise_error(IO::Buffer::LockedError, "Buffer is locked!")
    end
    buffer.free
    buffer.null?.should be_true
  end

  context "with a slice of a buffer" do
    it "nullifies the slice, not touching the buffer" do
      buffer = IO::Buffer.new(4)
      slice = buffer.slice(0, 2)

      slice.free
      slice.null?.should be_true
      buffer.null?.should be_false

      buffer.free
    end

    it "nullifies buffer, invalidating the slice" do
      buffer = IO::Buffer.new(4)
      slice = buffer.slice(0, 2)

      buffer.free
      slice.null?.should be_false
      slice.valid?.should be_false
    end
  end
end
