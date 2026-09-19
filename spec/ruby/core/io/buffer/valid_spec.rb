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

      it "keeps an empty range valid as the source grows and shrinks" do
        @buffer = IO::Buffer.new(0)
        slice = @buffer.slice(0, 0)

        slice.valid?.should == true

        @buffer.resize(1)
        slice.valid?.should == true
        slice.get_string.should == ""

        @buffer.resize(0)
        slice.valid?.should == true
        slice.get_string.should == ""
      end

      it "preserves a nested slice's range when the root grows" do
        @buffer = IO::Buffer.new(8)
        @buffer.set_string("ABCDEFGH")
        parent = @buffer.slice(1, 6)
        slice = parent.slice(1, 4)

        @buffer.resize(1 << 20)
        slice.valid?.should == true
        slice.get_string.should == "CDEF"
        slice.set_string("wxyz")
        @buffer.get_string(0, 8).should == "ABwxyzGH"
        parent.get_string.should == "BwxyzG"
      end

      it "becomes valid again at its original offset when a shrunk root regrows" do
        @buffer = IO::Buffer.new(8)
        slice = @buffer.slice(2, 4)

        @buffer.resize(5)
        slice.valid?.should == false
        slice.null?.should == true
        slice.size.should == 4
        -> { slice.get_string }.should.raise(IO::Buffer::InvalidatedError)
        -> { slice.set_string("xxxx") }.should.raise(IO::Buffer::InvalidatedError)

        @buffer.resize(8)
        @buffer.set_string("abcdefgh")
        slice.valid?.should == true
        slice.null?.should == false
        slice.get_string.should == "cdef"
      end

      it "refers to current contents when a freed root is allocated again" do
        @buffer = IO::Buffer.new(8)
        @buffer.set_string("ABCDEFGH")
        slice = @buffer.slice(2, 4)

        @buffer.free
        slice.valid?.should == false
        @buffer.resize(8)
        @buffer.set_string("abcdefgh")

        slice.valid?.should == true
        slice.get_string.should == "cdef"
        slice.set_string("wxyz")
        @buffer.get_string.should == "abwxyzgh"
      end

      it "resolves a new root allocation rather than the transferred allocation" do
        @buffer = IO::Buffer.new(8)
        @buffer.set_string("ABCDEFGH")
        slice = @buffer.slice(2, 4)
        previous = @buffer.transfer

        begin
          slice.valid?.should == false
          # Keep the old allocation alive so the new allocation cannot reuse
          # its address. The slice must resolve through the original root.
          @buffer.resize(8)
          @buffer.set_string("abcdefgh")

          slice.valid?.should == true
          slice.get_string.should == "cdef"
          slice.set_string("wxyz")
          @buffer.get_string.should == "abwxyzgh"
          previous.get_string.should == "ABCDEFGH"
        ensure
          previous.free
        end
      end

      it "keeps an empty range at offset zero valid after the root is freed" do
        @buffer = IO::Buffer.new(8)
        slice = @buffer.slice(0, 0)

        @buffer.free
        slice.valid?.should == true
        slice.null?.should == true
        slice.get_string.should == ""

        @buffer.resize(8)
        slice.valid?.should == true
        slice.null?.should == false
        slice.get_string.should == ""
      end

      it "is false when its empty range no longer belongs to the source" do
        @buffer = IO::Buffer.new(1)
        slice = @buffer.slice(1, 0)

        @buffer.resize(0)
        slice.valid?.should == false

        @buffer.resize(1)
        slice.valid?.should == true
        slice.empty?.should == true
        slice.get_string.should == ""
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
