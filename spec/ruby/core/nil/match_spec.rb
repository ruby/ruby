require_relative '../../spec_helper'

describe "NilClass#=~" do
  it "returns nil matching any object" do
    o = nil

    suppress_warning do
      (o =~ /Object/).should   be_nil
      (o =~ 'Object').should   be_nil
      (o =~ Object).should     be_nil
      (o =~ Object.new).should be_nil
      (o =~ nil).should        be_nil
      (o =~ false).should      be_nil
      (o =~ true).should       be_nil
    end
  end

  it "should not warn" do
    -> { nil =~ /a/ }.should_not complain(verbose: true)
  end
end
