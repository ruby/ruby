require_relative '../../spec_helper'

describe "Random::DEFAULT" do

  it "returns a random number generator" do
    Random::DEFAULT.should respond_to(:rand)
  end

  it "returns a Random instance" do
    Random::DEFAULT.should be_kind_of(Random)
  end

  it "changes seed on reboot" do
    seed1 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
    seed2 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
    seed1.should != seed2
  end
end
