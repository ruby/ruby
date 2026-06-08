require_relative '../../spec_helper'

describe "MatchData#length" do
  it "is an alias of MatchData#size" do
    MatchData.instance_method(:length).should == MatchData.instance_method(:size)
  end
end
