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
      @buffer.valid?.should == true
    end

    it "is true for a 0-size buffer" do
      @buffer = IO::Buffer.new(0)
      @buffer.valid?.should == true
    end

    it "is true for a freed buffer" do
      @buffer = IO::Buffer.new(4)
      @buffer.free
      @buffer.valid?.should == true
    end

    it "is true for a freed file-backed buffer" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        @buffer.valid?.should == true
        @buffer.free
        @buffer.valid?.should == true
      end
    end

    it "is true for a freed string-backed buffer" do
      @buffer = IO::Buffer.for("hello")
      @buffer.valid?.should == true
      @buffer.free
      @buffer.valid?.should == true
    end
  end

  # A slice tracks a logical [offset, length) range of its source. It becomes
  # invalid only if the source is freed, or resized so that the slice's range
  # no longer fits; it survives a resize that merely relocates the source.
  context "with a slice" do
    it "is true for a slice of a live buffer" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(0, 2)
      slice.valid?.should == true
    end

    ruby_version_is "4.1" do
      it "is true for an empty slice of an empty buffer" do
        @buffer = IO::Buffer.new(0)
        slice = @buffer.slice(0, 0)

        slice.valid?.should == true
        slice.get_string.should == ""
      end

      it "survives a resize that relocates the source" do
        @buffer = IO::Buffer.new(0)
        slice = @buffer.slice(0, 0)

        slice.valid?.should == true

        # Growing the source may relocate its allocation, but the slice's
        # [0, 0) range still exists within it, so the slice stays valid:
        @buffer.resize(1)
        slice.valid?.should == true
        slice.get_string.should == ""

        @buffer.resize(0)
        slice.valid?.should == true
        slice.get_string.should == ""
      end

      it "keeps referring to the same range after the source is relocated" do
        @buffer = IO::Buffer.new(8)
        @buffer.set_string("ABCDEFGH")
        slice = @buffer.slice(2, 4)
        slice.get_string.should == "CDEF"

        # A large grow is likely to relocate the source allocation; the slice
        # continues to refer to bytes [2, 6) of the (preserved) contents:
        @buffer.resize(1 << 20)
        slice.valid?.should == true
        slice.get_string.should == "CDEF"
      end

      it "is false when its empty range no longer belongs to the source" do
        @buffer = IO::Buffer.new(1)
        slice = @buffer.slice(1, 0)

        @buffer.resize(0)
        slice.valid?.should == false
      end
    end

    context "when buffer is resized" do
      it "is false when slice becomes outside the buffer" do
        @buffer = IO::Buffer.new(4)
        slice = @buffer.slice(2, 2)
        @buffer.resize(3)
        slice.valid?.should == false
      end
    end

    it "is false for a slice of a transferred buffer" do
      buffer = IO::Buffer.new(4)
      slice = buffer.slice(0, 2)
      @buffer = buffer.transfer
      slice.valid?.should == false
    end

    it "is false for a slice of a freed buffer" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(0, 2)
      @buffer.free
      slice.valid?.should == false
    end

    it "is independent of null? and empty?" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(0, 2)
      @buffer.free

      slice.valid?.should == false
      slice.empty?.should == false

      ruby_version_is ""..."4.1" do
        slice.null?.should == false
      end

      ruby_version_is "4.1" do
        slice.null?.should == true
      end
    end

    it "can be true for a non-null empty slice" do
      @buffer = IO::Buffer.new(4)
      slice = @buffer.slice(2, 0)

      slice.valid?.should == true
      slice.null?.should == false
      slice.empty?.should == true
    end

    it "is false for a slice of a freed file-backed buffer" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        slice = @buffer.slice(0, 2)
        slice.valid?.should == true
        @buffer.free
        slice.valid?.should == false
      end
    end

    ruby_version_is ""..."4.1" do
      it "is true for a slice of a freed string-backed buffer while string is alive" do
        @buffer = IO::Buffer.for("alive")
        slice = @buffer.slice(0, 2)
        slice.valid?.should == true
        @buffer.free
        slice.valid?.should == true
      end
    end

    ruby_version_is "4.1" do
      it "is false for a slice of a freed string-backed buffer" do
        @buffer = IO::Buffer.for("alive")
        slice = @buffer.slice(0, 2)
        slice.valid?.should == true
        @buffer.free
        slice.valid?.should == false
      end
    end

    # There probably should be a test with a garbage-collected string,
    # but it's not clear how to force that.

    it "needs to be reviewed for spec completeness"
  end
end
