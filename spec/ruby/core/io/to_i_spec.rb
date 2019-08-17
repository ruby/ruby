require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#to_i" do
  it "returns the numeric file descriptor of the given IO object" do
    $stdout.to_i.should == 1
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.to_i }.should raise_error(IOError)
  end
end
