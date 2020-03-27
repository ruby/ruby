require_relative '../../spec_helper'

describe "Random::DEFAULT" do
  it "returns a Random instance" do
    Random::DEFAULT.should be_an_instance_of(Random)
  end

  it "changes seed on reboot" do
    seed1 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
    seed2 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
    seed1.should != seed2
  end
end
