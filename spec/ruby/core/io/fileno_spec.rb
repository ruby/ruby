require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#fileno" do
  it "returns the numeric file descriptor of the given IO object" do
    $stdout.fileno.should == 1
  end

  it "raises IOError on closed stream" do
    lambda { IOSpecs.closed_io.fileno }.should raise_error(IOError)
  end
end
