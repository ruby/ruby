require_relative '../../spec_helper'

describe "MatchData#regexp" do
  it "returns a Regexp object" do
    m = 'haystack'.match(/hay/)
    m.regexp.should be_an_instance_of(Regexp)
  end

  it "returns the pattern used in the match" do
    m = 'haystack'.match(/hay/)
    m.regexp.should == /hay/
  end

  it "returns the same Regexp used to match" do
    r = /hay/
    m = 'haystack'.match(r)
    m.regexp.object_id.should == r.object_id
  end

  it "returns a Regexp for the result of gsub(String)" do
    'he[[o'.gsub('[', ']')
    $~.regexp.should == /\[/
  end
end
