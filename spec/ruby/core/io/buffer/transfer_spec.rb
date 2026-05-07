require_relative '../../../spec_helper'

describe "IO::Buffer#transfer" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  context "with a buffer created with .new" do
    it "transfers internal memory to a new buffer, nullifying the original" do
      buffer = IO::Buffer.new(4)
      info = buffer.to_s
      @buffer = buffer.transfer
      @buffer.to_s.should == info
      buffer.null?.should == true
    end

    it "transfers mapped memory to a new buffer, nullifying the original" do
      buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
      info = buffer.to_s
      @buffer = buffer.transfer
      @buffer.to_s.should == info
      buffer.null?.should == true
    end
  end

  context "with a file-backed buffer created with .map" do
    it "transfers mapped memory to a new buffer, nullifying the original" do
      File.open(__FILE__, "r") do |file|
        buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        info = buffer.to_s
        @buffer = buffer.transfer
        @buffer.to_s.should == info
        buffer.null?.should == true
      end
    end
  end

  context "with a String-backed buffer created with .for" do
    context "without a block" do
      it "transfers memory to a new buffer, nullifying the original" do
        buffer = IO::Buffer.for("test")
        info = buffer.to_s
        @buffer = buffer.transfer
        @buffer.to_s.should == info
        buffer.null?.should == true
      end
    end

    context "with a block" do
      it "transfers memory to a new buffer, breaking the transaction by nullifying the original" do
        IO::Buffer.for(+"test") do |buffer|
          info = buffer.to_s
          @buffer = buffer.transfer
          @buffer.to_s.should == info
          buffer.null?.should == true
        end
        @buffer.null?.should == false
      end
    end
  end

  context "with a String-backed buffer created with .string" do
    it "transfers memory to a new buffer, breaking the transaction by nullifying the original" do
      IO::Buffer.string(4) do |buffer|
        info = buffer.to_s
        @buffer = buffer.transfer
        @buffer.to_s.should == info
        buffer.null?.should == true
      end
      @buffer.null?.should == false
    end
  end

  it "allows multiple transfers" do
    buffer_1 = IO::Buffer.new(4)
    buffer_2 = buffer_1.transfer
    @buffer = buffer_2.transfer
    buffer_1.null?.should == true
    buffer_2.null?.should == true
    @buffer.null?.should == false
  end

  it "is disallowed while locked, raising IO::Buffer::LockedError" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked do
      -> { @buffer.transfer }.should.raise(IO::Buffer::LockedError, "Cannot transfer ownership of locked buffer!")
    end
  end

  context "with a slice of a buffer" do
    it "transfers source to a new slice, not touching the buffer" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(0, 2)
      @buffer.set_string("test")

      new_slice = slice.transfer
      slice.null?.should == true
      new_slice.null?.should == false
      @buffer.null?.should == false

      new_slice.set_string("ea")
      @buffer.get_string.should == "east"
    end

    it "nullifies buffer, invalidating the slice" do
      buffer = IO::Buffer.new(4)
      slice = buffer.slice(0, 2)
      @buffer = buffer.transfer

      slice.null?.should == false
      slice.valid?.should == false
      -> { slice.get_string }.should.raise(IO::Buffer::InvalidatedError, "Buffer has been invalidated!")
    end
  end
end
