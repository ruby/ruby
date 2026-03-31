require_relative '../../../spec_helper'

describe "IO::Buffer#valid?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  # Non-slices are always valid
  context "with a non-slice buffer" do
    it "is true for a regular buffer" do
      @buffer = IO::Buffer.new(4)
      @buffer.valid?.should be_true
    end

    it "is true for a 0-size buffer" do
      @buffer = IO::Buffer.new(0)
      @buffer.valid?.should be_true
    end

    it "is true for a freed buffer" do
      @buffer = IO::Buffer.new(4)
      @buffer.free
      @buffer.valid?.should be_true
    end

    it "is true for a freed file-backed buffer" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        @buffer.valid?.should be_true
        @buffer.free
        @buffer.valid?.should be_true
      end
    end

    it "is true for a freed string-backed buffer" do
      @buffer = IO::Buffer.for("hello")
      @buffer.valid?.should be_true
      @buffer.free
      @buffer.valid?.should be_true
    end
  end

  # "A buffer becomes invalid if it is a slice of another buffer (or string)
  # which has been freed or re-allocated at a different address."
  context "with a slice" do
    it "is true for a slice of a live buffer" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(0, 2)
      slice.valid?.should be_true
    end

    context "when buffer is resized" do
      it "is false when slice becomes outside the buffer" do
        @buffer = IO::Buffer.new(4)
        slice = @buffer.slice(2, 2)
        @buffer.resize(3)
        slice.valid?.should be_false
      end

      platform_is_not :linux do
        # This test does not cause a copy-resize on Linux.
        # `#resize` MAY cause the buffer to move, but there is no guarantee.
        it "is false when buffer is copied on resize" do
          @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
          slice = @buffer.slice(0, 2)
          @buffer.resize(8)
          slice.valid?.should be_false
        end
      end
    end

    it "is false for a slice of a transferred buffer" do
      buffer = IO::Buffer.new(4)
      slice = buffer.slice(0, 2)
      @buffer = buffer.transfer
      slice.valid?.should be_false
    end

    it "is false for a slice of a freed buffer" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(0, 2)
      @buffer.free
      slice.valid?.should be_false
    end

    it "is false for a slice of a freed file-backed buffer" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        slice = @buffer.slice(0, 2)
        slice.valid?.should be_true
        @buffer.free
        slice.valid?.should be_false
      end
    end

    it "is true for a slice of a freed string-backed buffer while string is alive" do
      @buffer = IO::Buffer.for("alive")
      slice = @buffer.slice(0, 2)
      slice.valid?.should be_true
      @buffer.free
      slice.valid?.should be_true
    end

    # There probably should be a test with a garbage-collected string,
    # but it's not clear how to force that.

    it "needs to be reviewed for spec completeness"
  end
end
