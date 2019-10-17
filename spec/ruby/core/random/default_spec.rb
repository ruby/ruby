require_relative '../../spec_helper'

describe "Random::DEFAULT" do
  it "returns a Random instance" do
    Random::DEFAULT.should be_an_instance_of(Random)
  end
end
