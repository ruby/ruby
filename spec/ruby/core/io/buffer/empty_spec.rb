require_relative '../../../spec_helper'
require_relative 'shared/null_and_empty'

describe "IO::Buffer#empty?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  it_behaves_like :io_buffer_null_and_empty, :empty?

  it "is true for a 0-length String-backed buffer created with .for" do
    @buffer = IO::Buffer.for("")
    @buffer.empty?.should be_true
  end

  ruby_version_is "3.3" do
    it "is true for a 0-length String-backed buffer created with .string" do
      IO::Buffer.string(0) do |buffer|
        buffer.empty?.should be_true
      end
    end
  end

  it "is true for a 0-length slice of a buffer with size > 0" do
    @buffer = IO::Buffer.new(4)
    @buffer.slice(3, 0).empty?.should be_true
  end
end
