require_relative '../../spec_helper'

describe "MatchData#to_s" do
  it "returns the entire matched string" do
    /(.)(.)(\d+)(\d)/.match("THX1138.").to_s.should == "HX1138"
  end
end
