require_relative '../../spec_helper'

ruby_version_is ''...'3.2' do
  describe "Random::DEFAULT" do
    it "returns a random number generator" do
      suppress_warning do
        Random::DEFAULT.should respond_to(:rand)
      end
    end

    it "changes seed on reboot" do
      seed1 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
      seed2 = ruby_exe('p Random::DEFAULT.seed', options: '--disable-gems')
      seed1.should != seed2
    end
  end
end
