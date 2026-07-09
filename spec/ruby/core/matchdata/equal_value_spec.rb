require_relative '../../spec_helper'

describe "MatchData#==" do
  it "returns true if both operands have equal target strings, patterns, and match positions" do
    a = 'haystack'.match(/hay/)
    b = 'haystack'.match(/hay/)
    a.==(b).should == true
  end

  it "returns false if the operands have different target strings" do
    a = 'hay'.match(/hay/)
    b = 'haystack'.match(/hay/)
    a.==(b).should == false
  end

  it "returns false if the operands have different patterns" do
    a = 'haystack'.match(/h.y/)
    b = 'haystack'.match(/hay/)
    a.==(b).should == false
  end

  it "returns false if the argument is not a MatchData object" do
    a = 'haystack'.match(/hay/)
    a.==(Object.new).should == false
  end
end
