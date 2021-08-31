require_relative '../../spec_helper'

describe "Random::DEFAULT" do

  it "returns a random number generator" do
    suppress_warning do
      Random::DEFAULT.should respond_to(:rand)
    end
  end

  ruby_version_is ''...'3.0' do
    it "returns a Random instance" do
      suppress_warning do
        Random::DEFAULT.should be_an_instance_of(Random)
      end
    end
  end

  ruby_version_is '3.0' do
    it "refers to the Random class" do
      suppress_warning do
        Random::DEFAULT.should.equal?(Random)
      end
    end

    it "is deprecated" do
      -> {
        Random::DEFAULT.should.equal?(Random)
      }.should complain(/constant Random::DEFAULT is deprecated/)
    end
  end

  it "changes seed on reboot" do
    seed1 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
    seed2 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
    seed1.should != seed2
  end
end
