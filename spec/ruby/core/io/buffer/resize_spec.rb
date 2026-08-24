require_relative '../../../spec_helper'

describe "IO::Buffer#resize" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  context "with a buffer created with .new" do
    it "resizes internal buffer, preserving type" do
      @buffer = IO::Buffer.new(4)
      @buffer.resize(IO::Buffer::PAGE_SIZE)
      @buffer.size.should == IO::Buffer::PAGE_SIZE
      @buffer.internal?.should == true
      @buffer.mapped?.should == false
    end

    platform_is :linux do
      it "resizes mapped buffer, preserving type" do
        @buffer = IO::Buffer.new(IO::Buffer::PAGE_SIZE, IO::Buffer::MAPPED)
        @buffer.resize(4)
        @buffer.size.should == 4
        @buffer.internal?.should == false
        @buffer.mapped?.should == true
      end
    end

    platform_is_not :linux do
      it "resizes mapped buffer, changing type to internal" do
        @buffer = IO::Buffer.new(IO::Buffer::PAGE_SIZE, IO::Buffer::MAPPED)
        @buffer.resize(4)
        @buffer.size.should == 4
        @buffer.internal?.should == true
        @buffer.mapped?.should == false
      end
    end
  end

  context "with a file-backed buffer created with .map" do
    it "disallows resizing shared buffer, raising IO::Buffer::AccessError" do
      File.open(__FILE__, "r+") do |file|
        @buffer = IO::Buffer.map(file)
        -> { @buffer.resize(10) }.should.raise(IO::Buffer::AccessError, "Cannot resize external buffer!")
      end
    end

    it "resizes private buffer, discarding excess contents" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::PRIVATE)
        @buffer.resize(10)
        @buffer.size.should == 10
        @buffer.get_string.should == "require_re"
        @buffer.resize(12)
        @buffer.size.should == 12
        @buffer.get_string.should == "require_re\0\0"
      end
    end
  end

  context "with a String-backed buffer created with .for" do
    context "without a block" do
      it "disallows resizing, raising IO::Buffer::AccessError" do
        @buffer = IO::Buffer.for(+"test")
        -> { @buffer.resize(10) }.should.raise(IO::Buffer::AccessError, "Cannot resize external buffer!")
      end
    end

    context "with a block" do
      it "disallows resizing, raising IO::Buffer::AccessError" do
        IO::Buffer.for(+'test') do |buffer|
          -> { buffer.resize(10) }.should.raise(IO::Buffer::AccessError, "Cannot resize external buffer!")
        end
      end
    end
  end

  context "with a String-backed buffer created with .string" do
    it "disallows resizing, raising IO::Buffer::AccessError" do
      IO::Buffer.string(4) do |buffer|
        -> { buffer.resize(10) }.should.raise(IO::Buffer::AccessError, "Cannot resize external buffer!")
      end
    end
  end

  context "with a null buffer" do
    it "allows resizing a 0-sized buffer, creating a regular buffer according to new size" do
      @buffer = IO::Buffer.new(0)
      @buffer.resize(IO::Buffer::PAGE_SIZE)
      @buffer.size.should == IO::Buffer::PAGE_SIZE
      @buffer.internal?.should == false
      @buffer.mapped?.should == true
    end

    it "allows resizing after a free, creating a regular buffer according to new size" do
      @buffer = IO::Buffer.for("test")
      @buffer.free
      @buffer.resize(10)
      @buffer.size.should == 10
      @buffer.internal?.should == true
      @buffer.mapped?.should == false
    end
  end

  it "allows resizing to 0, freeing memory" do
    @buffer = IO::Buffer.new(4)
    @buffer.resize(0)
    @buffer.null?.should == true
  end

  it "can be called repeatedly" do
    @buffer = IO::Buffer.new(4)
    @buffer.resize(10)
    @buffer.resize(27)
    @buffer.resize(1)
    @buffer.size.should == 1
  end

  ruby_version_is "4.1" do
    it "raises FrozenError without resizing a frozen buffer" do
      buffer = IO::Buffer.new(4)
      buffer.set_string("test")
      buffer.freeze

      -> { buffer.resize(8) }.should.raise(FrozenError)
      buffer.size.should == 4
      buffer.get_string.should == "test"
    end
  end

  it "always clears extra memory" do
    @buffer = IO::Buffer.new(4)
    @buffer.set_string("test")
    # This should not cause a re-allocation, just a technical resizing,
    # even with very aggressive memory allocation.
    @buffer.resize(2)
    @buffer.resize(4)
    @buffer.get_string.should == "te\0\0"
  end

  it "is disallowed while locked, raising IO::Buffer::LockedError" do
    @buffer = IO::Buffer.new(4)
    @buffer.locked do
      -> { @buffer.resize(10) }.should.raise(IO::Buffer::LockedError, "Cannot resize locked buffer!")
    end
  end

  it "raises ArgumentError if size is negative" do
    @buffer = IO::Buffer.new(4)
    -> { @buffer.resize(-1) }.should.raise(ArgumentError, "Size can't be negative!")
  end

  it "raises TypeError if size is not an Integer" do
    @buffer = IO::Buffer.new(4)
    -> { @buffer.resize(nil) }.should.raise(TypeError, "not an Integer")
    -> { @buffer.resize(10.0) }.should.raise(TypeError, "not an Integer")
  end

  ruby_version_is "4.1" do
    context "with a slice of a buffer" do
      it "changes the size of the view without modifying the source" do
        @buffer = IO::Buffer.for("abcdef").dup
        slice = @buffer.slice(2, 2)

        slice.resize(4).should.equal?(slice)
        slice.get_string.should == "cdef"
        @buffer.get_string.should == "abcdef"

        slice.resize(1)
        slice.get_string.should == "c"
      end

      it "does not allocate when resized to zero" do
        @buffer = IO::Buffer.for("abcdef").dup
        slice = @buffer.slice(2, 2)

        slice.resize(0)
        slice.should_not.null?
        slice.should.empty?
        slice.should.valid?

        slice.resize(4)
        slice.get_string.should == "cdef"
      end

      it "raises ArgumentError when the resized view exceeds the source" do
        @buffer = IO::Buffer.for("abcdef").dup
        slice = @buffer.slice(2, 2)

        -> { slice.resize(5) }.should.raise(
          ArgumentError,
          "Resized slice exceeds its source buffer!"
        )

        slice.get_string.should == "cd"
      end

      it "can be resized while the source allocation is locked" do
        @buffer = IO::Buffer.for("abcdef").dup
        slice = @buffer.slice(2, 2)

        slice.locked do
          slice.resize(4)
          slice.get_string.should == "cdef"
        end
      end

      it "preserves read-only access" do
        @buffer = IO::Buffer.for("abcdef")
        slice = @buffer.slice(2, 2)

        slice.resize(4)
        slice.should.readonly?
        slice.get_string.should == "cdef"
      end

      it "uses the retained root buffer as the boundary for nested slices" do
        @buffer = IO::Buffer.for("abcdef").dup
        parent = @buffer.slice(1, 2)
        slice = parent.slice(1, 1)

        slice.resize(4)
        slice.get_string.should == "cdef"
      end
    end
  end
end
