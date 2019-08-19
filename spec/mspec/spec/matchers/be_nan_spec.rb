require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/guards'
require 'mspec/helpers'
require 'mspec/matchers'

describe BeNaNMatcher do
  it "matches when actual is NaN" do
    BeNaNMatcher.new.matches?(nan_value).should == true
  end

  it "does not match when actual is not NaN" do
    BeNaNMatcher.new.matches?(1.0).should == false
    BeNaNMatcher.new.matches?(0).should == false
  end

  it "provides a useful failure message" do
    matcher = BeNaNMatcher.new
    matcher.matches?(0)
    matcher.failure_message.should == ["Expected 0", "to be NaN"]
  end

  it "provides a useful negative failure message" do
    matcher = BeNaNMatcher.new
    matcher.matches?(nan_value)
    matcher.negative_failure_message.should == ["Expected NaN", "not to be NaN"]
  end
end
