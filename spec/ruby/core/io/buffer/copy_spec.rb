require_relative '../../../spec_helper'

describe "IO::Buffer#copy" do
  ruby_version_is "4.1" do
    it "raises FrozenError without modifying a frozen buffer" do
      buffer = IO::Buffer.new(4)
      buffer.set_string("test")
      buffer.freeze

      IO::Buffer.for("fail") do |source|
        -> { buffer.copy(source, 0) }.should.raise(FrozenError)
      end

      buffer.get_string.should == "test"
    end
  end
end
