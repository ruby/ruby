require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#closed_write?" do
  it "returns true if self is not writable" do
    io = StringIO.new(+"example", "r+")
    io.close_read
    io.closed_write?.should == false
    io.close_write
    io.closed_write?.should == true
  end
end
