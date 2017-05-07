require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe SignedZeroMatcher do
  it "matches when actual is zero and has the correct sign" do
    SignedZeroMatcher.new(1).matches?(0.0).should == true
    SignedZeroMatcher.new(-1).matches?(-0.0).should == true
  end

  it "does not match when actual is non-zero" do
    SignedZeroMatcher.new(1).matches?(1.0).should == false
    SignedZeroMatcher.new(-1).matches?(-1.0).should == false
  end

  it "does not match when actual is zero but has the incorrect sign" do
    SignedZeroMatcher.new(1).matches?(-0.0).should == false
    SignedZeroMatcher.new(-1).matches?(0.0).should == false
  end

  it "provides a useful failure message" do
    matcher = SignedZeroMatcher.new(-1)
    matcher.matches?(0.0)
    matcher.failure_message.should == ["Expected 0.0", "to be -0.0"]
  end

  it "provides a useful negative failure message" do
    matcher = SignedZeroMatcher.new(-1)
    matcher.matches?(-0.0)
    matcher.negative_failure_message.should == ["Expected -0.0", "not to be -0.0"]
  end
end
