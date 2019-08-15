require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#close" do
  before :each do
    @io = StringIOSpecs.build
  end

  it "returns nil" do
    @io.close.should be_nil
  end

  it "prevents further reading and/or writing" do
    @io.close
    -> { @io.read(1) }.should raise_error(IOError)
    -> { @io.write('x') }.should raise_error(IOError)
  end

  it "does not raise anything when self was already closed" do
    @io.close
    -> { @io.close }.should_not raise_error(IOError)
  end
end
