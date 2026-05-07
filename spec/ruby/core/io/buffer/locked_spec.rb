require_relative '../../../spec_helper'

describe "IO::Buffer#locked" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  context "when buffer is locked" do
    it "allows reading and writing operations on the buffer" do
      @buffer = IO::Buffer.new(4)
      @buffer.set_string("test")
      @buffer.locked do
        @buffer.get_string.should == "test"
        @buffer.set_string("meat")
      end
      @buffer.get_string.should == "meat"
    end

    it "disallows operations changing buffer itself, raising IO::Buffer::LockedError" do
      @buffer = IO::Buffer.new(4)
      @buffer.locked do
        # Just an example, each method is responsible for checking the lock state.
        -> { @buffer.resize(8) }.should.raise(IO::Buffer::LockedError)
      end
    end
  end

  it "disallows reentrant locking, raising IO::Buffer::LockedError" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked do
      -> { @buffer.locked {} }.should.raise(IO::Buffer::LockedError, "Buffer already locked!")
    end
  end

  it "does not propagate to buffer's slices" do
    @buffer = IO::Buffer.new(4)
    slice = @buffer.slice(0, 2)
    @buffer.locked do
      @buffer.locked?.should == true
      slice.locked?.should == false
      slice.locked { slice.locked?.should == true }
    end
  end

  it "does not propagate backwards from buffer's slices" do
    @buffer = IO::Buffer.new(4)
    slice = @buffer.slice(0, 2)
    slice.locked do
      slice.locked?.should == true
      @buffer.locked?.should == false
      @buffer.locked { @buffer.locked?.should == true }
    end
  end
end

describe "IO::Buffer#locked?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is false by default" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked?.should == false
  end

  it "is true only inside of #locked block" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked do
      @buffer.locked?.should == true
    end
    @buffer.locked?.should == false
  end
end
