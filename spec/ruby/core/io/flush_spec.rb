require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#flush" do
  it "raises IOError on closed stream" do
    lambda { IOSpecs.closed_io.flush }.should raise_error(IOError)
  end
end
