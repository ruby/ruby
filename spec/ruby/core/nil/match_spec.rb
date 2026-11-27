require_relative '../../spec_helper'

describe "NilClass#=~" do
  it "returns nil matching any object" do
    o = nil

    suppress_warning do
      (o =~ /Object/).should == nil
      (o =~ 'Object').should == nil
      (o =~ Object).should == nil
      (o =~ Object.new).should == nil
      (o =~ nil).should == nil
      (o =~ false).should == nil
      (o =~ true).should == nil
    end
  end

  it "should not warn" do
    -> { nil =~ /a/ }.should_not complain(verbose: true)
  end
end
