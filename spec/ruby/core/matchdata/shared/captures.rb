require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :matchdata_captures, shared: true do
  it "returns an array of the match captures" do
    /(.)(.)(\d+)(\d)/.match("THX1138.").send(@method).should == ["H","X","113","8"]
  end

  it "returns instances of String when given a String subclass" do
    str = MatchDataSpecs::MyString.new("THX1138: The Movie")
    /(.)(.)(\d+)(\d)/.match(str).send(@method).each { |c| c.should be_an_instance_of(String) }
  end
end
