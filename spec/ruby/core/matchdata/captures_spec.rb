require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "MatchData#captures" do
  it "returns an array of the match captures" do
    /(.)(.)(\d+)(\d)/.match("THX1138.").captures.should == ["H","X","113","8"]
  end

  ruby_version_is "3.0" do
    it "returns instances of String when given a String subclass" do
      str = MatchDataSpecs::MyString.new("THX1138: The Movie")
      /(.)(.)(\d+)(\d)/.match(str).captures.each { |c| c.should be_an_instance_of(String) }
    end
  end
end
