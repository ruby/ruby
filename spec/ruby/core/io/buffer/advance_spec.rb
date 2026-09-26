require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "IO::Buffer#advance" do
    before :each do
      @buffer = IO::Buffer.new(8)
      @buffer.set_string("abcdefgh")
    end

    after :each do
      @buffer.free
    end

    it "consumes the front of a slice without changing its source or siblings" do
      slice = @buffer.slice(1, 6)
      sibling = @buffer.slice(1, 6)

      slice.advance(2).should.equal?(slice)
      slice.size.should == 4
      slice.get_string.should == "defg"
      sibling.get_string.should == "bcdefg"
      @buffer.get_string.should == "abcdefgh"
    end

    it "uses the advanced offset when creating a nested slice" do
      parent = @buffer.slice(1, 6)
      parent.advance(2)
      slice = parent.slice(1, 2)
      slice.advance(1)
      slice.get_string.should == "f"
      parent.get_string.should == "defg"

      @buffer.resize(32)
      slice.set_string("X")
      @buffer.get_string(0, 8).should == "abcdeXgh"
    end

    it "allows a locked view to advance and resize within its root's bounds" do
      slice = @buffer.slice(1, 4)
      slice.locked do
        slice.advance(2)
        slice.get_string.should == "de"
        slice.resize(4)
        slice.get_string.should == "defg"
        slice.should.locked?
        @buffer.should.locked?
        -> { @buffer.resize(16) }.should.raise(IO::Buffer::LockedError)
        -> { @buffer.free }.should.raise(IO::Buffer::LockedError)
      end
      @buffer.should_not.locked?
    end

    it "advances a read-only String-backed buffer without modifying the String" do
      string = "abcdef".freeze
      IO::Buffer.for(string) do |view|
        view.locked do
          view.advance(2).should.equal?(view)
          view.get_string.should == "cdef"
          view.should.readonly?
          view.should.locked?
          -> { view.set_string("X") }.should.raise(IO::Buffer::AccessError)
          string.should == "abcdef"
        end
      end
    end

    it "allows read-only slices to advance and resize while locked" do
      IO::Buffer.for("abcdef".freeze) do |source|
        slice = source.slice(0, 4)
        slice.locked do
          slice.advance(2)
          slice.resize(4)
          slice.get_string.should == "cdef"
          slice.should.readonly?
          source.should.locked?
        end
      end
    end

    it "leaves an empty view at the end after consuming its entire size" do
      slice = @buffer.slice(2, 3)
      slice.advance(3)
      slice.should.empty?
      slice.should.valid?
      slice.should_not.null?
      slice.get_string.should == ""
      slice.advance(0).should.equal?(slice)
      slice.resize(3)
      slice.get_string.should == "fgh"
      -> { slice.resize(4) }.should.raise(ArgumentError)
    end

    it "permits a zero advance on an empty slice of a null buffer" do
      @buffer.resize(0)
      slice = @buffer.slice(0, 0)
      slice.advance(0).should.equal?(slice)
      slice.should.valid?
      slice.should.null?
      slice.get_string.should == ""
    end

    it "rejects owning buffers even for a zero advance" do
      -> { @buffer.advance(0) }.should.raise(IO::Buffer::AccessError)
      -> { @buffer.advance(1) }.should.raise(IO::Buffer::AccessError)
      @buffer.size.should == 8
      @buffer.get_string.should == "abcdefgh"
    end

    it "rejects mapped allocations even when they are external" do
      File.open(__FILE__, "r") do |file|
        mapping = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        begin
          mapping.should.external?
          mapping.should.mapped?
          -> { mapping.advance(1) }.should.raise(IO::Buffer::AccessError)
        ensure
          mapping.free
        end
      end
    end

    it "rejects amounts outside the view without changing it" do
      slice = @buffer.slice(2, 4)
      -> { slice.advance(5) }.should.raise(ArgumentError)
      -> { slice.advance(-1) }.should.raise(ArgumentError)
      slice.size.should == 4
      slice.get_string.should == "cdef"
    end

    it "rejects non-integer amounts" do
      slice = @buffer.slice
      -> { slice.advance(nil) }.should.raise(TypeError)
      -> { slice.advance(1.5) }.should.raise(TypeError)
      slice.get_string.should == "abcdefgh"
    end

    it "rejects frozen views without advancing them" do
      slice = @buffer.slice.freeze
      -> { slice.advance(1) }.should.raise(FrozenError)
      slice.get_string.should == "abcdefgh"
    end

    it "rejects invalid views, including a zero advance" do
      slice = @buffer.slice(2, 4)
      @buffer.free
      -> { slice.advance(0) }.should.raise(IO::Buffer::InvalidatedError)
      -> { slice.advance(1) }.should.raise(IO::Buffer::InvalidatedError)
      slice.size.should == 4

      @buffer.resize(8)
      @buffer.set_string("abcdefgh")
      slice.get_string.should == "cdef"
    end

    it "preserves the advanced logical offset when its root is reallocated" do
      slice = @buffer.slice(1, 6)
      slice.advance(2)
      previous = @buffer.transfer
      begin
        @buffer.resize(8)
        @buffer.set_string("ABCDEFGH")
        slice.get_string.should == "DEFG"
        previous.get_string.should == "abcdefgh"
      ensure
        previous.free
      end
    end
  end
end
