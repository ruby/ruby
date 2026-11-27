require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#pos" do
  before :each do
    @io = StringIOSpecs.build
  end

  it "returns the current byte offset" do
    @io.getc
    @io.pos.should == 1
    @io.read(7)
    @io.pos.should == 8
  end
end

describe "StringIO#pos=" do
  before :each do
    @io = StringIOSpecs.build
  end

  it "updates the current byte offset" do
    @io.pos = 26
    @io.read(1).should == "r"
  end

  it "raises an EINVAL if given a negative argument" do
    -> { @io.pos = -10 }.should.raise(Errno::EINVAL)
  end

  it "updates the current byte offset after reaching EOF" do
    @io.read
    @io.pos = 26
    @io.read(1).should == "r"
  end
end
