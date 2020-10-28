require_relative '../../spec_helper'

describe "Time#sunday?" do
  it "returns true if time represents Sunday" do
    Time.local(2000, 1, 2).should.sunday?
  end

  it "returns false if time doesn't represent Sunday" do
    Time.local(2000, 1, 1).should_not.sunday?
  end
end
