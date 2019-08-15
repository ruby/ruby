require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe BeTrueMatcher do
  it "matches when actual is true" do
    BeTrueMatcher.new.matches?(true).should == true
  end

  it "does not match when actual is not true" do
    BeTrueMatcher.new.matches?("").should == false
    BeTrueMatcher.new.matches?(false).should == false
    BeTrueMatcher.new.matches?(nil).should == false
    BeTrueMatcher.new.matches?(0).should == false
  end

  it "provides a useful failure message" do
    matcher = BeTrueMatcher.new
    matcher.matches?("some string")
    matcher.failure_message.should == ["Expected \"some string\"", "to be true"]
  end

  it "provides a useful negative failure message" do
    matcher = BeTrueMatcher.new
    matcher.matches?(true)
    matcher.negative_failure_message.should == ["Expected true", "not to be true"]
  end
end
