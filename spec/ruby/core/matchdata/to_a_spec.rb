require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "MatchData#to_a" do
  it "returns an array of matches" do
    /(.)(.)(\d+)(\d)/.match("THX1138.").to_a.should == ["HX1138", "H", "X", "113", "8"]
  end

  it "returns instances of String when given a String subclass" do
    str = MatchDataSpecs::MyString.new("THX1138.")
    /(.)(.)(\d+)(\d)/.match(str)[0..-1].to_a.each { |m| m.should be_an_instance_of(String) }
  end
end
