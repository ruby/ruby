require_relative '../../../spec_helper'

describe "IO::Buffer#set_value" do
  ruby_version_is "4.1" do
    it "raises FrozenError without modifying a frozen buffer" do
      buffer = IO::Buffer.new(4)
      buffer.set_string("test")
      buffer.freeze

      -> { buffer.set_value(:U8, 0, 0) }.should.raise(FrozenError)
      buffer.get_string.should == "test"
    end
  end
end
