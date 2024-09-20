require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "MatchData#to_s" do
  it "returns the entire matched string" do
    /(.)(.)(\d+)(\d)/.match("THX1138.").to_s.should == "HX1138"
  end

  it "returns an instance of String when given a String subclass" do
    str = MatchDataSpecs::MyString.new("THX1138.")
    /(.)(.)(\d+)(\d)/.match(str).to_s.should be_an_instance_of(String)
  end
end
