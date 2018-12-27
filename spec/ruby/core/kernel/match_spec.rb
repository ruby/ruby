require_relative '../../spec_helper'

describe "Kernel#=~" do
  verbose = $VERBOSE
  before :each do
    $VERBOSE = nil
  end
  after :each do
    verbose = $VERBOSE
  end

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
