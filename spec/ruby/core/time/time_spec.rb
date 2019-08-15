require_relative '../../spec_helper'

describe "Time" do
  it "includes Comparable" do
    Time.include?(Comparable).should == true
  end
end
