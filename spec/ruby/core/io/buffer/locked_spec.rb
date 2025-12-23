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
        -> { @buffer.resize(8) }.should raise_error(IO::Buffer::LockedError)
      end
    end
  end

  it "disallows reentrant locking, raising IO::Buffer::LockedError" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked do
      -> { @buffer.locked {} }.should raise_error(IO::Buffer::LockedError, "Buffer already locked!")
    end
  end

  it "does not propagate to buffer's slices" do
    @buffer = IO::Buffer.new(4)
    slice = @buffer.slice(0, 2)
    @buffer.locked do
      @buffer.locked?.should be_true
      slice.locked?.should be_false
      slice.locked { slice.locked?.should be_true }
    end
  end

  it "does not propagate backwards from buffer's slices" do
    @buffer = IO::Buffer.new(4)
    slice = @buffer.slice(0, 2)
    slice.locked do
      slice.locked?.should be_true
      @buffer.locked?.should be_false
      @buffer.locked { @buffer.locked?.should be_true }
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
    @buffer.locked?.should be_false
  end

  it "is true only inside of #locked block" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked do
      @buffer.locked?.should be_true
    end
    @buffer.locked?.should be_false
  end
end
