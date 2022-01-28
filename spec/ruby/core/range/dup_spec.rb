require_relative '../../spec_helper'

describe "Range#dup" do
  it "duplicates the range" do
    copy = (1..3).dup
    copy.begin.should == 1
    copy.end.should == 3
    copy.should_not.exclude_end?

    copy = ("a"..."z").dup
    copy.begin.should == "a"
    copy.end.should == "z"
    copy.should.exclude_end?
  end

  it "creates an unfrozen range" do
    (1..2).dup.should_not.frozen?
    (1..).dup.should_not.frozen?
    Range.new(1, 2).dup.should_not.frozen?
  end
end
