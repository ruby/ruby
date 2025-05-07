require_relative '../../spec_helper'

describe "Regexp.linear_time?" do
  it "returns true if matching can be done in linear time" do
    Regexp.linear_time?(/a/).should == true
    Regexp.linear_time?('a').should == true
  end

  it "return false if matching can't be done in linear time" do
    Regexp.linear_time?(/(a)\1/).should == false
    Regexp.linear_time?("(a)\\1").should == false
  end

  it "accepts flags for string argument" do
    Regexp.linear_time?('a', Regexp::IGNORECASE).should == true
  end

  it "warns about flags being ignored for regexp arguments" do
    -> {
      Regexp.linear_time?(/a/, Regexp::IGNORECASE)
    }.should complain(/warning: flags ignored/)
  end
end
