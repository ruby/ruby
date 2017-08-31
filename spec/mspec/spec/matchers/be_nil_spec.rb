require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe BeNilMatcher do
  it "matches when actual is nil" do
    BeNilMatcher.new.matches?(nil).should == true
  end

  it "does not match when actual is not nil" do
    BeNilMatcher.new.matches?("").should == false
    BeNilMatcher.new.matches?(false).should == false
    BeNilMatcher.new.matches?(0).should == false
  end

  it "provides a useful failure message" do
    matcher = BeNilMatcher.new
    matcher.matches?("some string")
    matcher.failure_message.should == ["Expected \"some string\"", "to be nil"]
  end

  it "provides a useful negative failure message" do
    matcher = BeNilMatcher.new
    matcher.matches?(nil)
    matcher.negative_failure_message.should == ["Expected nil", "not to be nil"]
  end
end
