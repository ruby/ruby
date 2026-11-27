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
    it "reflects its source's current permissions" do
      @buffer = IO::Buffer.new(8)
      parent = @buffer.slice(0, 8)
      slice = parent.slice(2, 4)

      @buffer.free
      @buffer.send(:initialize, 8, IO::Buffer::INTERNAL | IO::Buffer::READONLY)

      slice.should.valid?
      slice.should.readonly?
      -> { slice.set_string("test") }.should.raise(IO::Buffer::AccessError)

      @buffer.free
      @buffer.resize(8)

      slice.should.valid?
      slice.should_not.readonly?
      slice.set_string("test")
      @buffer.get_string.should == "\0\0test\0\0"
    end

    it "is true for a slice whose source is frozen" do
      buffer = IO::Buffer.new(8)
      slice = buffer.slice(2, 4).slice(1, 2)
      buffer.freeze

      slice.should.readonly?
      -> { slice.set_string("test") }.should.raise(IO::Buffer::AccessError)
    end
  end
end
