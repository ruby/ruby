require_relative '../../spec_helper'

describe "Time#monday?" do
  it "returns true if time represents Monday" do
    Time.local(2000, 1, 3).should.monday?
  end

  it "returns false if time doesn't represent Monday" do
    Time.local(2000, 1, 1).should_not.monday?
  end
end
