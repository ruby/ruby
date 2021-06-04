require_relative '../../spec_helper'

describe "Time#saturday?" do
  it "returns true if time represents Saturday" do
    Time.local(2000, 1, 1).should.saturday?
  end

  it "returns false if time doesn't represent Saturday" do
    Time.local(2000, 1, 2).should_not.saturday?
  end
end
