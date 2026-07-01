require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#closed?" do
  it "returns true if self is completely closed" do
    io = StringIO.new(+"example", "r+")
    io.close_read
    io.closed?.should == false
    io.close_write
    io.closed?.should == true

    io = StringIO.new(+"example", "r+")
    io.close
    io.closed?.should == true
  end
end
