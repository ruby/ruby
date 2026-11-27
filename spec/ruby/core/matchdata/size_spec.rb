require_relative '../../spec_helper'

describe "MatchData#size" do
  it "should return the number of elements in the match array" do
    /(.)(.)(\d+)(\d)/.match("THX1138.").size.should == 5
  end
end
