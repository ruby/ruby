require_relative '../../spec_helper'

describe "MatchData#deconstruct" do
  it "is an alias of MatchData#captures" do
    MatchData.instance_method(:deconstruct).should == MatchData.instance_method(:captures)
  end
end
