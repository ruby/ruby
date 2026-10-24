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
    @buffer.null?.should == false
  end

  it "is false for a 0-length String-backed buffer created with .string" do
    IO::Buffer.string(0) do |buffer|
      buffer.null?.should == false
    end
  end

  it "is false for a 0-length slice of a buffer with size > 0" do
    @buffer = IO::Buffer.new(4)
    @buffer.slice(3, 0).null?.should == false
  end

  it "reflects an invalid slice whose source was freed" do
    @buffer = IO::Buffer.new(4)
    slice = @buffer.slice(0, 2)
    @buffer.free

    slice.valid?.should == false

    ruby_version_is ""..."4.1" do
      # Address-based slices retain the recorded (non-null) address.
      slice.null?.should == false
    end

    ruby_version_is "4.1" do
      # Offset-based slices resolve their base from the (now freed) source,
      # so they resolve to a null address.
      slice.null?.should == true
    end
  end
end
