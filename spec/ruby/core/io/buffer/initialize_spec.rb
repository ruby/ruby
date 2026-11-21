require_relative '../../../spec_helper'

describe "IO::Buffer#initialize" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "creates a new zero-filled buffer with default size" do
    @buffer = IO::Buffer.new
    @buffer.size.should == IO::Buffer::DEFAULT_SIZE
    @buffer.each(:U8).should.all? { |_offset, value| value.eql?(0) }
  end

  it "creates a buffer with default state" do
    @buffer = IO::Buffer.new

    @buffer.should_not.external?

    @buffer.should_not.shared?
    @buffer.should_not.private?
    @buffer.should_not.readonly?

    @buffer.should_not.empty?
    @buffer.should_not.null?

    @buffer.should_not.locked?
    @buffer.should.valid?
  end

  context "with size argument" do
    it "creates a new internal buffer if size is less than IO::Buffer::PAGE_SIZE" do
      size = IO::Buffer::PAGE_SIZE - 1
      @buffer = IO::Buffer.new(size)
      @buffer.size.should == size
      @buffer.should_not.empty?

      @buffer.should.internal?
      @buffer.should_not.mapped?
    end

    it "creates a new mapped buffer if size is greater than or equal to IO::Buffer::PAGE_SIZE" do
      size = IO::Buffer::PAGE_SIZE
      @buffer = IO::Buffer.new(size)
      @buffer.size.should == size
      @buffer.should_not.empty?

      @buffer.should_not.internal?
      @buffer.should.mapped?
    end

    it "creates a null buffer if size is 0" do
      @buffer = IO::Buffer.new(0)
      @buffer.should.null?
      @buffer.should.empty?
    end

    it "raises TypeError if size is not an Integer" do
      -> { IO::Buffer.new(nil) }.should.raise(TypeError, "not an Integer")
      -> { IO::Buffer.new(10.0) }.should.raise(TypeError, "not an Integer")
    end

    it "raises ArgumentError if size is negative" do
      -> { IO::Buffer.new(-1) }.should.raise(ArgumentError, "Size can't be negative!")
    end
  end

  context "with size and flags arguments" do
    it "forces mapped buffer with IO::Buffer::MAPPED flag" do
      @buffer = IO::Buffer.new(IO::Buffer::PAGE_SIZE - 1, IO::Buffer::MAPPED)
      @buffer.should.mapped?
      @buffer.should_not.internal?
      @buffer.should_not.empty?
    end

    it "forces internal buffer with IO::Buffer::INTERNAL flag" do
      @buffer = IO::Buffer.new(IO::Buffer::PAGE_SIZE, IO::Buffer::INTERNAL)
      @buffer.should.internal?
      @buffer.should_not.mapped?
      @buffer.should_not.empty?
    end

    it "allows extra flags" do
      @buffer = IO::Buffer.new(10, IO::Buffer::MAPPED | IO::Buffer::SHARED | IO::Buffer::READONLY)
      @buffer.should.mapped?
      @buffer.should.shared?
      @buffer.should.readonly?
    end

    ruby_version_is "4.1" do
      it "infers IO::Buffer::MAPPED from IO::Buffer::SHARED" do
        @buffer = IO::Buffer.new(10, IO::Buffer::SHARED)
        @buffer.should.mapped?
        @buffer.should.shared?
      end

      it "infers IO::Buffer::MAPPED from IO::Buffer::PRIVATE" do
        @buffer = IO::Buffer.new(10, IO::Buffer::PRIVATE)
        @buffer.should.mapped?
        @buffer.should.private?
      end
    end

    it "ignores flags if size is 0" do
      @buffer = IO::Buffer.new(0, 0xffff)
      @buffer.should.null?
      @buffer.should.empty?

      @buffer.should_not.internal?
      @buffer.should_not.mapped?
      @buffer.should_not.external?

      @buffer.should_not.shared?
      @buffer.should_not.readonly?

      @buffer.should_not.locked?
      @buffer.should.valid?
    end

    ruby_version_is ""..."4.1" do
      it "raises IO::Buffer::AllocationError if neither IO::Buffer::MAPPED nor IO::Buffer::INTERNAL is given" do
        -> { IO::Buffer.new(10, IO::Buffer::READONLY) }.should.raise(IO::Buffer::AllocationError, "Could not allocate buffer!")
        -> { IO::Buffer.new(10, 0) }.should.raise(IO::Buffer::AllocationError, "Could not allocate buffer!")
      end
    end

    ruby_version_is "4.1" do
      it "infers the allocation mode if neither IO::Buffer::MAPPED nor IO::Buffer::INTERNAL is given" do
        @buffer = IO::Buffer.new(10, IO::Buffer::READONLY)
        @buffer.should.internal?
        @buffer.should.readonly?

        @buffer.free
        @buffer = IO::Buffer.new(IO::Buffer::PAGE_SIZE, 0)
        @buffer.should.mapped?
      end

      it "raises ArgumentError if both IO::Buffer::MAPPED and IO::Buffer::INTERNAL are given" do
        flags = IO::Buffer::INTERNAL | IO::Buffer::MAPPED
        -> { IO::Buffer.new(10, flags) }.should.raise(ArgumentError, "Flags can't include both IO::Buffer::INTERNAL and IO::Buffer::MAPPED!")
      end

      it "raises ArgumentError if IO::Buffer::EXTERNAL is given" do
        flags = IO::Buffer::INTERNAL | IO::Buffer::EXTERNAL
        -> { IO::Buffer.new(10, flags) }.should.raise(ArgumentError, "IO::Buffer::EXTERNAL can't be used with IO::Buffer.new!")
      end

      it "raises ArgumentError if mapping flags are given with IO::Buffer::INTERNAL" do
        flags = IO::Buffer::INTERNAL | IO::Buffer::SHARED
        -> { IO::Buffer.new(10, flags) }.should.raise(ArgumentError, "IO::Buffer::SHARED and IO::Buffer::PRIVATE require IO::Buffer::MAPPED!")

        flags = IO::Buffer::INTERNAL | IO::Buffer::PRIVATE
        -> { IO::Buffer.new(10, flags) }.should.raise(ArgumentError, "IO::Buffer::SHARED and IO::Buffer::PRIVATE require IO::Buffer::MAPPED!")
      end

      it "raises ArgumentError if both IO::Buffer::SHARED and IO::Buffer::PRIVATE are given" do
        flags = IO::Buffer::SHARED | IO::Buffer::PRIVATE
        -> { IO::Buffer.new(10, flags) }.should.raise(ArgumentError, "Flags can't include both IO::Buffer::SHARED and IO::Buffer::PRIVATE!")
      end
    end

    it "raises ArgumentError if flags is negative" do
      -> { IO::Buffer.new(10, -1) }.should.raise(ArgumentError, "Flags can't be negative!")
    end

    it "raises TypeError with non-Integer flags" do
      -> { IO::Buffer.new(10, 0.0) }.should.raise(TypeError, "not an Integer")
    end
  end
end
