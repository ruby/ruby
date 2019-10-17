require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/guards'
require 'mspec/helpers'
require 'mspec/matchers'

describe InfinityMatcher do
  it "matches when actual is infinite and has the correct sign" do
    InfinityMatcher.new(1).matches?(infinity_value).should == true
    InfinityMatcher.new(-1).matches?(-infinity_value).should == true
  end

  it "does not match when actual is not infinite" do
    InfinityMatcher.new(1).matches?(1.0).should == false
    InfinityMatcher.new(-1).matches?(-1.0).should == false
  end

  it "does not match when actual is infinite but has the incorrect sign" do
    InfinityMatcher.new(1).matches?(-infinity_value).should == false
    InfinityMatcher.new(-1).matches?(infinity_value).should == false
  end

  it "provides a useful failure message" do
    matcher = InfinityMatcher.new(-1)
    matcher.matches?(0)
    matcher.failure_message.should == ["Expected 0", "to be -Infinity"]
  end

  it "provides a useful negative failure message" do
    matcher = InfinityMatcher.new(1)
    matcher.matches?(infinity_value)
    matcher.negative_failure_message.should == ["Expected Infinity", "not to be Infinity"]
  end
end
