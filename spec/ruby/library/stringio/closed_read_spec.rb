require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#closed_read?" do
  it "returns true if self is not readable" do
    io = StringIO.new("example", "r+")
    io.close_write
    io.closed_read?.should be_false
    io.close_read
    io.closed_read?.should be_true
  end
end
