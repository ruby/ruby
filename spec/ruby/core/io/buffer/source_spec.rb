require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "IO::Buffer#source" do
    it "is nil for an allocated buffer" do
      buffer = IO::Buffer.new(8)
      begin
        buffer.source.should == nil
      ensure
        buffer.free
      end
    end

    it "returns the immediate parent of a nested slice" do
      buffer = IO::Buffer.new(8)
      begin
        parent = buffer.slice(1, 6)
        child = parent.slice(1, 2)
        parent.source.should.equal?(buffer)
        child.source.should.equal?(parent)
        buffer.free
        child.should_not.valid?
        child.source.should.equal?(parent)
      ensure
        buffer.free
      end
    end

    it "returns the original String in the block form of IO::Buffer.for" do
      string = +"abcdefgh"
      IO::Buffer.for(string) do |buffer|
        buffer.source.should.equal?(string)
        buffer.slice.source.should.equal?(buffer)
      end
    end

    it "returns a Ruby-visible frozen backing String in the non-block form" do
      [0, 8, 1024].each do |size|
        string = "x" * size
        buffer = IO::Buffer.for(string)
        begin
          buffer.source.should.is_a?(String)
          buffer.source.should.frozen?
          buffer.source.should == "x" * size
          buffer.source.should.equal?(buffer.source)
          string.replace("changed!")
          buffer.source.should == "x" * size
        ensure
          buffer.free
        end
      end
    end

    it "preserves the encoding of the backing String" do
      string = +"\u00e9"
      buffer = IO::Buffer.for(string)
      begin
        buffer.source.encoding.should == string.encoding
        buffer.source.should == string
      ensure
        buffer.free
      end
    end

    it "clears the receiver's source when freed" do
      buffer = IO::Buffer.new(8)
      begin
        slice = buffer.slice
        slice.free
        slice.source.should == nil
        buffer.size.should == 8
      ensure
        buffer.free
      end
    end

    it "moves the source reference to the transferred view" do
      buffer = IO::Buffer.new(8)
      transferred = nil
      begin
        slice = buffer.slice
        transferred = slice.transfer
        slice.source.should == nil
        transferred.source.should.equal?(buffer)
      ensure
        transferred&.free
        buffer.free
      end
    end

    it "does not expose a source setter" do
      buffer = IO::Buffer.new(0)
      buffer.respond_to?(:source=).should == false
    end
  end
end
