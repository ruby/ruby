require_relative '../../../spec_helper'

describe "IO::Buffer#readonly?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it "is true for a buffer created with READONLY flag" do
    @buffer = IO::Buffer.new(12, IO::Buffer::INTERNAL | IO::Buffer::READONLY)
    @buffer.readonly?.should == true
  end

  it "is true for a buffer that is non-writable" do
    @buffer = IO::Buffer.for("string")
    @buffer.readonly?.should == true
  end

  it "is false for a modifiable buffer" do
    @buffer = IO::Buffer.new(12)
    @buffer.readonly?.should == false
  end

  it "is false for a null buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.readonly?.should == false
  end

  ruby_version_is "4.1" do
    it "reflects a revived slice's current root permissions" do
      @buffer = IO::Buffer.new(8)
      slice = @buffer.slice(2, 4)
      @buffer.free
      @buffer.send(:initialize, 8, IO::Buffer::INTERNAL | IO::Buffer::READONLY)

      slice.should.valid?
      slice.should.readonly?
      slice.get_string.should == "\0" * 4
      -> { slice.set_string("TEST") }.should.raise(IO::Buffer::AccessError)
      -> { slice.set_value(:U8, 0, 42) }.should.raise(IO::Buffer::AccessError)

      slice.locked do
        slice.advance(1)
        slice.resize(4)
        slice.get_string.should == "\0" * 4
        slice.should.readonly?
      end
    end

    it "follows its root when read-only storage is replaced by writable storage" do
      @buffer = IO::Buffer.new(8, IO::Buffer::INTERNAL | IO::Buffer::READONLY)
      slice = @buffer.slice(2, 4)
      slice.should.readonly?
      @buffer.free
      @buffer.resize(8)
      @buffer.set_string("abcdefgh")

      @buffer.should_not.readonly?
      slice.should.valid?
      slice.should_not.readonly?
      slice.get_string.should == "cdef"
      slice.set_string("TEST")
      @buffer.get_string.should == "abTESTgh"
    end

    it "derives nested slice permissions from the root without copying them" do
      @buffer = IO::Buffer.new(8)
      parent = @buffer.slice(2, 4)
      @buffer.free
      @buffer.send(:initialize, 8, IO::Buffer::INTERNAL | IO::Buffer::READONLY)
      child = parent.slice(1, 2)
      parent.should.readonly?
      child.should.readonly?

      @buffer.free
      @buffer.resize(8)
      @buffer.set_string("abcdefgh")
      parent.should_not.readonly?
      parent.set_string("WXYZ")
      child.get_string.should == "XY"
      child.should_not.readonly?
      child.set_string("!!")
      @buffer.get_string.should == "abW!!Zgh"
    end

    it "is true for a slice whose source has been frozen" do
      buffer = IO::Buffer.new(8)
      buffer.set_string("abcdefgh")
      slice = buffer.slice(2, 4)
      buffer.freeze

      slice.should.readonly?
      -> { slice.set_string("TEST") }.should.raise(IO::Buffer::AccessError)
      slice.advance(1)
      slice.resize(4)
      slice.get_string.should == "defg"
    end
  end
end
