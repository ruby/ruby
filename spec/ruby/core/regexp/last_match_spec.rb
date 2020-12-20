require_relative '../../spec_helper'

describe "Regexp.last_match" do
  it "returns MatchData instance when not passed arguments" do
    /c(.)t/ =~ 'cat'

    Regexp.last_match.should be_kind_of(MatchData)
  end

  it "returns the nth field in this MatchData when passed an Integer" do
    /c(.)t/ =~ 'cat'
    Regexp.last_match(1).should == 'a'
  end
end
