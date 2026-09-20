require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "IO::Buffer#source" do
    after :each do
      @buffer&.free
      @buffer = nil
    end

    it "returns nil for a source-less buffer" do
      @buffer = IO::Buffer.new(8)

      @buffer.source.should == nil
    end

    it "returns each slice's immediate parent" do
      @buffer = IO::Buffer.new(8)
      parent = @buffer.slice(1, 6)
      child = parent.slice(2, 2)

      parent.source.should.equal?(@buffer)
      child.source.should.equal?(parent)
    end

    it "retains its immediate parent" do
      @buffer = IO::Buffer.new(8)
      parent = @buffer.slice(1, 6)
      child = parent.slice(2, 2)
      parent_id = parent.object_id
      parent = nil

      GC.start

      child.source.object_id.should == parent_id
    end

    it "returns a visible String source" do
      string = "test".freeze
      @buffer = IO::Buffer.for(string)

      @buffer.source.should.equal?(string)
    end

    it "returns a Ruby-visible frozen snapshot for a mutable String source" do
      string = +"test"
      @buffer = IO::Buffer.for(string)

      source = @buffer.source
      source.should.kind_of?(String)
      source.should.frozen?
      source.should_not.equal?(string)
      source.should == "test"
      source.encoding.should == string.encoding

      string.replace("else")
      source.should == "test"
      @buffer.get_string.should == "test"
    end

    it "does not provide a source setter" do
      @buffer = IO::Buffer.new(8)

      @buffer.should_not.respond_to?(:source=)
    end

    it "retains a mutable String source while yielding a writable buffer" do
      string = +"test"

      IO::Buffer.for(string) do |buffer|
        buffer.source.should.equal?(string)
      end
    end

    it "validates descendants against each current parent view" do
      @buffer = IO::Buffer.new(8)
      @buffer.set_string("abcdefgh")
      parent = @buffer.slice(1, 6)
      child = parent.slice(2, 2)

      child.get_string.should == "de"

      parent.resize(3)
      child.should_not.valid?

      parent.resize(6)
      child.should.valid?
      child.get_string.should == "de"
    end

    it "resolves deeply nested sources without recursion" do
      @buffer = IO::Buffer.new(4)
      @buffer.set_string("test")
      slice = @buffer

      4096.times { slice = slice.slice(0, 4) }

      slice.should.valid?
      slice.get_string.should == "test"
      slice.source.should.kind_of?(IO::Buffer)
      slice.should_not.readonly?

      slice.locked do
        @buffer.should.locked?
      end
    end

    it "invalidates descendants when a parent is freed" do
      @buffer = IO::Buffer.new(8)
      parent = @buffer.slice(1, 6)
      child = parent.slice(2, 2)

      parent.free

      child.should_not.valid?
      @buffer.should.valid?
    end

    it "keeps a String-backed buffer's source alive" do
      string = "test".freeze
      @buffer = IO::Buffer.for(string)

      @buffer.source.should.equal?(string)
      @buffer.free
      string.should == "test"
    it "clears a Buffer's source when freed, without detaching its slices" do
      buffer = IO::Buffer.for("abcdefgh")
      slice = buffer.slice
      buffer.free
      buffer.source.should == nil
      slice.source.should.equal?(buffer)
      slice.should_not.valid?
    end

    it "moves a Buffer's source reference when its storage is transferred" do
      buffer = IO::Buffer.for("abcdefgh")
      source = buffer.source
      transferred = nil
      begin
        transferred = buffer.transfer
        buffer.source.should == nil
        transferred.source.should.equal?(source)
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
