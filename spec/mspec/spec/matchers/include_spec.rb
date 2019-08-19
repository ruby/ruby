require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe IncludeMatcher do
  it "matches when actual includes expected" do
    IncludeMatcher.new(2).matches?([1,2,3]).should == true
    IncludeMatcher.new("b").matches?("abc").should == true
  end

  it "does not match when actual does not include expected" do
    IncludeMatcher.new(4).matches?([1,2,3]).should == false
    IncludeMatcher.new("d").matches?("abc").should == false
  end

  it "matches when actual includes all expected" do
    IncludeMatcher.new(3, 2, 1).matches?([1,2,3]).should == true
    IncludeMatcher.new("a", "b", "c").matches?("abc").should == true
  end

  it "does not match when actual does not include all expected" do
    IncludeMatcher.new(3, 2, 4).matches?([1,2,3]).should == false
    IncludeMatcher.new("a", "b", "c", "d").matches?("abc").should == false
  end

  it "provides a useful failure message" do
    matcher = IncludeMatcher.new(5, 2)
    matcher.matches?([1,2,3])
    matcher.failure_message.should == ["Expected [1, 2, 3]", "to include 5"]
  end

  it "provides a useful negative failure message" do
    matcher = IncludeMatcher.new(1, 2, 3)
    matcher.matches?([1,2,3])
    matcher.negative_failure_message.should == ["Expected [1, 2, 3]", "not to include 3"]
  end
end
