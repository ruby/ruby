require_relative '../../spec_helper'

describe "Kernel#=~" do
  it "returns nil matching any object" do
    o = Object.new

    (o =~ /Object/).should   be_nil
    (o =~ 'Object').should   be_nil
    (o =~ Object).should     be_nil
    (o =~ Object.new).should be_nil
    (o =~ nil).should        be_nil
    (o =~ true).should       be_nil
  end
end
