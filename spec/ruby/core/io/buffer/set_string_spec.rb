require_relative '../../../spec_helper'

describe "IO::Buffer#set_string" do
  ruby_version_is "4.1" do
    it "raises FrozenError without modifying a frozen buffer" do
      buffer = IO::Buffer.new(4)
      buffer.set_string("test")
      buffer.freeze

      -> { buffer.set_string("fail") }.should.raise(FrozenError)
      buffer.get_string.should == "test"
    end

    it "raises FrozenError without modifying the source of a frozen buffer" do
      string = +"test"

      IO::Buffer.for(string) do |buffer|
        buffer.freeze

        -> { buffer.set_string("fail") }.should.raise(FrozenError)
      end

      string.should == "test"
    end

    it "raises FrozenError on a clone of a frozen buffer" do
      buffer = IO::Buffer.new(4)
      buffer.set_string("test")

      clone = buffer.freeze.clone

      -> { clone.set_string("fail") }.should.raise(FrozenError)
      clone.get_string.should == "test"
    end

    it "raises FrozenError rather than IO::Buffer::AccessError when also read-only" do
      buffer = IO::Buffer.for("test".freeze)

      -> { buffer.set_string("fail") }.should.raise(IO::Buffer::AccessError)

      buffer.freeze
      -> { buffer.set_string("fail") }.should.raise(FrozenError)
    end
  end
end
