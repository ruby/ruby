require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe BeFalseMatcher do
  it "matches when actual is false" do
    BeFalseMatcher.new.matches?(false).should == true
  end

  it "does not match when actual is not false" do
    BeFalseMatcher.new.matches?("").should == false
    BeFalseMatcher.new.matches?(true).should == false
    BeFalseMatcher.new.matches?(nil).should == false
    BeFalseMatcher.new.matches?(0).should == false
  end

  it "provides a useful failure message" do
    matcher = BeFalseMatcher.new
    matcher.matches?("some string")
    matcher.failure_message.should == ["Expected \"some string\"", "to be false"]
  end

  it "provides a useful negative failure message" do
    matcher = BeFalseMatcher.new
    matcher.matches?(false)
    matcher.negative_failure_message.should == ["Expected false", "not to be false"]
  end
end
