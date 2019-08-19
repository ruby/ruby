require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe BeEmptyMatcher do
  it "matches when actual is empty" do
    BeEmptyMatcher.new.matches?("").should == true
  end

  it "does not match when actual is not empty" do
    BeEmptyMatcher.new.matches?([10]).should == false
  end

  it "provides a useful failure message" do
    matcher = BeEmptyMatcher.new
    matcher.matches?("not empty string")
    matcher.failure_message.should == ["Expected \"not empty string\"", "to be empty"]
  end

  it "provides a useful negative failure message" do
    matcher = BeEmptyMatcher.new
    matcher.matches?("")
    matcher.negative_failure_message.should == ["Expected \"\"", "not to be empty"]
  end
end

