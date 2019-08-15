require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe IncludeAnyOfMatcher do
  it "matches when actual includes expected" do
    IncludeAnyOfMatcher.new(2).matches?([1,2,3]).should == true
    IncludeAnyOfMatcher.new("b").matches?("abc").should == true
  end

  it "does not match when actual does not include expected" do
    IncludeAnyOfMatcher.new(4).matches?([1,2,3]).should == false
    IncludeAnyOfMatcher.new("d").matches?("abc").should == false
  end

  it "matches when actual includes all expected" do
    IncludeAnyOfMatcher.new(3, 2, 1).matches?([1,2,3]).should == true
    IncludeAnyOfMatcher.new("a", "b", "c").matches?("abc").should == true
  end

  it "matches when actual includes any expected" do
    IncludeAnyOfMatcher.new(3, 4, 5).matches?([1,2,3]).should == true
    IncludeAnyOfMatcher.new("c", "d", "e").matches?("abc").should == true
  end

  it "does not match when actual does not include any expected" do
    IncludeAnyOfMatcher.new(4, 5).matches?([1,2,3]).should == false
    IncludeAnyOfMatcher.new("de").matches?("abc").should == false
  end

  it "provides a useful failure message" do
    matcher = IncludeAnyOfMatcher.new(5, 6)
    matcher.matches?([1,2,3])
    matcher.failure_message.should == ["Expected [1, 2, 3]", "to include any of [5, 6]"]
  end

  it "provides a useful negative failure message" do
    matcher = IncludeAnyOfMatcher.new(1, 2, 3)
    matcher.matches?([1,2])
    matcher.negative_failure_message.should == ["Expected [1, 2]", "not to include any of [1, 2, 3]"]
  end
end
