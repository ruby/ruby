require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "IO::Buffer#advance" do
    after :each do
      @buffer&.free
      @buffer = nil
    end

    it "advances a String-backed buffer without changing its source" do
      @buffer = IO::Buffer.for("test")
      source = @buffer.source

      @buffer.advance(1).should.equal?(@buffer)
      @buffer.size.should == 3
      @buffer.get_string.should == "est"
      @buffer.source.should.equal?(source)
      source.should == "test"
    end

    it "advances nested slices relative to their immediate parents" do
      @buffer = IO::Buffer.for("abcdef").dup
      parent = @buffer.slice(1, 5)
      child = parent.slice(1, 4)

      child.advance(2)

      child.get_string.should == "ef"
      parent.get_string.should == "bcdef"
      @buffer.get_string.should == "abcdef"
    end

    it "allows advancing read-only views" do
      @buffer = IO::Buffer.for("test")

      @buffer.should.readonly?
      @buffer.advance(2)
      @buffer.get_string.should == "st"
    end

    it "allows advancing while the source allocation is locked" do
      @buffer = IO::Buffer.new(4)
      @buffer.set_string("test")
      slice = @buffer.slice

      @buffer.locked do
        slice.advance(1)
        slice.should.locked?
        slice.get_string.should == "est"
      end
    end

    it "allows advancing by the full size" do
      @buffer = IO::Buffer.for("test")

      @buffer.advance(@buffer.size)

      @buffer.should.valid?
      @buffer.should.empty?
      @buffer.get_string.should == ""
    end

    it "rejects advancing an owning buffer" do
      @buffer = IO::Buffer.new(4)

      -> { @buffer.advance(1) }.should.raise(IO::Buffer::AccessError)
      @buffer.size.should == 4
    end

    it "rejects negative and out-of-bounds amounts without changing the view" do
      @buffer = IO::Buffer.for("test")

      -> { @buffer.advance(-1) }.should.raise(ArgumentError, "Amount can't be negative!")
      -> { @buffer.advance(5) }.should.raise(ArgumentError, "Advance amount exceeds buffer size!")
      @buffer.get_string.should == "test"
    end

    it "rejects advancing an invalid view without changing it" do
      @buffer = IO::Buffer.new(8)
      slice = @buffer.slice(2, 4)
      @buffer.resize(1)

      -> { slice.advance(1) }.should.raise(IO::Buffer::InvalidatedError)
      slice.size.should == 4
    end

    it "rejects advancing a frozen view" do
      buffer = IO::Buffer.for("test")
      buffer.freeze

      -> { buffer.advance(1) }.should.raise(FrozenError)
      buffer.get_string.should == "test"
    end

    it "keeps progress when an exception unwinds the caller" do
      @buffer = IO::Buffer.for("test")

      begin
        @buffer.advance(2)
        raise "stop"
      rescue RuntimeError => error
        error.message.should == "stop"
      end

      @buffer.get_string.should == "st"
    end
  end
end
