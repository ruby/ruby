require File.expand_path('../../../spec_helper', __FILE__)

describe "MatchData#values_at" do
  it "returns an array of the matching value" do
    /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(0, 2, -2).should == ["HX1138", "X", "113"]
  end

  describe "when passed a Range" do
    it "returns an array of the matching value" do
      /(.)(.)(\d+)(\d)/.match("THX1138: The Movie").values_at(2..4, 0..1).should == ["X", "113", "8", "HX1138", "H"]
    end
  end
end
