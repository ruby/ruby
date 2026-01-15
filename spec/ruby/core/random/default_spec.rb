require_relative '../../spec_helper'

describe "Random::DEFAULT" do
  it "is no longer defined" do
    Random.should_not.const_defined?(:DEFAULT)
  end
end
