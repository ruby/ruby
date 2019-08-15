require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#fcntl" do
  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.fcntl(5, 5) }.should raise_error(IOError)
  end
end
