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
      -> { IO::Buffer.new(nil) }.should raise_error(TypeError, "not an Integer")
      -> { IO::Buffer.new(10.0) }.should raise_error(TypeError, "not an Integer")
    end

    it "raises ArgumentError if size is negative" do
      -> { IO::Buffer.new(-1) }.should raise_error(ArgumentError, "Size can't be negative!")
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
      @buffer = IO::Buffer.new(10, IO::Buffer::INTERNAL | IO::Buffer::SHARED | IO::Buffer::READONLY)
      @buffer.should.internal?
      @buffer.should.shared?
      @buffer.should.readonly?
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

    it "raises IO::Buffer::AllocationError if neither IO::Buffer::MAPPED nor IO::Buffer::INTERNAL is given" do
      -> { IO::Buffer.new(10, IO::Buffer::READONLY) }.should raise_error(IO::Buffer::AllocationError, "Could not allocate buffer!")
      -> { IO::Buffer.new(10, 0) }.should raise_error(IO::Buffer::AllocationError, "Could not allocate buffer!")
    end

    it "raises ArgumentError if flags is negative" do
      -> { IO::Buffer.new(10, -1) }.should raise_error(ArgumentError, "Flags can't be negative!")
    end

    it "raises TypeError with non-Integer flags" do
      -> { IO::Buffer.new(10, 0.0) }.should raise_error(TypeError, "not an Integer")
    end
  end
end
