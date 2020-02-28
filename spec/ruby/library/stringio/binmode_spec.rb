require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#binmode" do
  it "returns self" do
    io = StringIO.new("example")
    io.binmode.should equal(io)
  end

  it "changes external encoding to BINARY" do
    io = StringIO.new
    io.external_encoding.should == Encoding.find('locale')
    io.binmode
    io.external_encoding.should == Encoding::BINARY
  end

  it "does not set internal encoding" do
    io = StringIO.new
    io.internal_encoding.should == nil
    io.binmode
    io.internal_encoding.should == nil
  end
end
