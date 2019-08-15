require_relative '../../spec_helper'

describe "Range#dup" do
  it "duplicates the range" do
    copy = (1..3).dup
    copy.begin.should == 1
    copy.end.should == 3
    copy.exclude_end?.should == false

    copy = ("a"..."z").dup
    copy.begin.should == "a"
    copy.end.should == "z"
    copy.exclude_end?.should == true
  end
end
