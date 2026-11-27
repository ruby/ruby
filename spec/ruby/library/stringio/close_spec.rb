require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#close" do
  before :each do
    @io = StringIOSpecs.build
  end

  it "returns nil" do
    @io.close.should == nil
  end

  it "prevents further reading and/or writing" do
    @io.close
    -> { @io.read(1) }.should.raise(IOError)
    -> { @io.write('x') }.should.raise(IOError)
  end

  it "does not raise anything when self was already closed" do
    @io.close
    -> { @io.close }.should_not.raise(IOError)
  end
end
