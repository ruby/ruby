require_relative '../../spec_helper'

describe "Random.urandom" do
  it "returns a String" do
    Random.urandom(1).should be_an_instance_of(String)
  end

  it "returns a String of the length given as argument" do
    Random.urandom(15).length.should == 15
  end

  it "raises an ArgumentError on a negative size" do
    -> {
      Random.urandom(-1)
    }.should raise_error(ArgumentError)
  end

  it "returns a binary String" do
    Random.urandom(15).encoding.should == Encoding::BINARY
  end

  it "returns a random binary String" do
    Random.urandom(12).should_not == Random.urandom(12)
  end
end
