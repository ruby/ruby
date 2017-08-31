require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe RespondToMatcher do
  it "matches when actual does respond_to? expected" do
    RespondToMatcher.new(:to_s).matches?(Object.new).should == true
    RespondToMatcher.new(:inject).matches?([]).should == true
    RespondToMatcher.new(:[]).matches?(1).should == true
    RespondToMatcher.new(:[]=).matches?("string").should == true
  end

  it "does not match when actual does not respond_to? expected" do
    RespondToMatcher.new(:to_i).matches?(Object.new).should == false
    RespondToMatcher.new(:inject).matches?(1).should == false
    RespondToMatcher.new(:non_existent_method).matches?([]).should == false
    RespondToMatcher.new(:[]=).matches?(1).should == false
  end

  it "provides a useful failure message" do
    matcher = RespondToMatcher.new(:non_existent_method)
    matcher.matches?('string')
    matcher.failure_message.should == [
      "Expected \"string\" (String)", "to respond to non_existent_method"]
  end

  it "provides a useful negative failure message" do
    matcher = RespondToMatcher.new(:to_i)
    matcher.matches?(4.0)
    matcher.negative_failure_message.should == [
      "Expected 4.0 (Float)", "not to respond to to_i"]
  end
end
