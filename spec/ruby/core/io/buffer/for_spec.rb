require_relative '../../../spec_helper'

describe "IO::Buffer.for" do
  before :each do
    @string = +"för striñg"
  end

  after :each do
    @buffer&.free
    @buffer = nil
  end

  context "without a block" do
    it "copies string's contents, creating a separate read-only buffer" do
      @buffer = IO::Buffer.for(@string)

      @buffer.size.should == @string.bytesize
      @buffer.get_string.should == @string.b

      @string[0] = "d"
      @buffer.get_string(0, 1).should == "f".b

      -> { @buffer.set_string("d") }.should raise_error(IO::Buffer::AccessError, "Buffer is not writable!")
    end

    it "creates an external, read-only buffer" do
      @buffer = IO::Buffer.for(@string)

      @buffer.should_not.internal?
      @buffer.should_not.mapped?
      @buffer.should.external?

      @buffer.should_not.empty?
      @buffer.should_not.null?

      @buffer.should_not.shared?
      @buffer.should_not.private?
      @buffer.should.readonly?

      @buffer.should_not.locked?
      @buffer.should.valid?
    end
  end

  context "with a block" do
    it "returns the last value in the block" do
      value =
        IO::Buffer.for(@string) do |buffer|
          buffer.size * 3
        end
      value.should == @string.bytesize * 3
    end

    it "frees the buffer at the end of the block" do
      IO::Buffer.for(@string) do |buffer|
        @buffer = buffer
        @buffer.should_not.null?
      end
      @buffer.should.null?
    end

    context "if string is not frozen" do
      it "creates a modifiable string-backed buffer" do
        IO::Buffer.for(@string) do |buffer|
          buffer.size.should == @string.bytesize
          buffer.get_string.should == @string.b

          buffer.should_not.readonly?

          buffer.set_string("ghost shell")
          @string.should == "ghost shellg"
        end
      end

      it "locks the original string to prevent modification" do
        IO::Buffer.for(@string) do |_buffer|
          -> { @string[0] = "t" }.should raise_error(RuntimeError, "can't modify string; temporarily locked")
        end
        @string[1] = "u"
        @string.should == "fur striñg"
      end
    end

    context "if string is frozen" do
      it "creates a read-only string-backed buffer" do
        IO::Buffer.for(@string.freeze) do |buffer|
          buffer.should.readonly?

          -> { buffer.set_string("ghost shell") }.should raise_error(IO::Buffer::AccessError, "Buffer is not writable!")
        end
      end
    end
  end
end
