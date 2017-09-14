require File.expand_path('../../../spec_helper', __FILE__)

describe "Random::DEFAULT" do
  it "returns a Random instance" do
    Random::DEFAULT.should be_an_instance_of(Random)
  end
end
