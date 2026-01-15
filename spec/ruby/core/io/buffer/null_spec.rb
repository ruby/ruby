require_relative '../../../spec_helper'
require_relative 'shared/null_and_empty'

describe "IO::Buffer#null?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it_behaves_like :io_buffer_null_and_empty, :null?

  it "is false for a 0-length String-backed buffer created with .for" do
    @buffer = IO::Buffer.for("")
    @buffer.null?.should be_false
  end

  ruby_version_is "3.3" do
    it "is false for a 0-length String-backed buffer created with .string" do
      IO::Buffer.string(0) do |buffer|
        buffer.null?.should be_false
      end
    end
  end

  it "is false for a 0-length slice of a buffer with size > 0" do
    @buffer = IO::Buffer.new(4)
    @buffer.slice(3, 0).null?.should be_false
  end
end
