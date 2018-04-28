require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#close_write" do
  before :each do
    @io = StringIO.new("example")
  end

  it "returns nil" do
    @io.close_write.should be_nil
  end

  it "prevents further writing" do
    @io.close_write
    lambda { @io.write('x') }.should raise_error(IOError)
  end

  it "allows further reading" do
    @io.close_write
    @io.read(1).should == 'e'
  end

  it "raises an IOError when in read-only mode" do
    io = StringIO.new("example", "r")
    lambda { io.close_write }.should raise_error(IOError)

    io = StringIO.new("example")
    io.close_write
    io.close_write.should == nil
  end
end
