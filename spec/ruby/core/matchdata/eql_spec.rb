require_relative '../../spec_helper'

describe "MatchData#eql?" do
  it "is an alias of MatchData#==" do
    MatchData.instance_method(:eql?).should == MatchData.instance_method(:==)
  end
end
