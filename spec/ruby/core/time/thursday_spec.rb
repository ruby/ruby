require_relative '../../spec_helper'

describe "Time#thursday?" do
  it "returns true if time represents Thursday" do
    Time.local(2000, 1, 6).should.thursday?
  end

  it "returns false if time doesn't represent Thursday" do
    Time.local(2000, 1, 1).should_not.thursday?
  end
end
