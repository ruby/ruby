require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe EqlMatcher do
  it "matches when actual is eql? to expected" do
    EqlMatcher.new(1).matches?(1).should == true
    EqlMatcher.new(1.5).matches?(1.5).should == true
    EqlMatcher.new("red").matches?("red").should == true
    EqlMatcher.new(:blue).matches?(:blue).should == true
    EqlMatcher.new(Object).matches?(Object).should == true

    o = Object.new
    EqlMatcher.new(o).matches?(o).should == true
  end

  it "does not match when actual is not eql? to expected" do
    EqlMatcher.new(1).matches?(1.0).should == false
    EqlMatcher.new(Hash).matches?(Object).should == false
  end

  it "provides a useful failure message" do
    matcher = EqlMatcher.new("red")
    matcher.matches?("red")
    matcher.failure_message.should == ["Expected \"red\"", "to have same value and type as \"red\""]
  end

  it "provides a useful negative failure message" do
    matcher = EqlMatcher.new(1)
    matcher.matches?(1.0)
    matcher.negative_failure_message.should == ["Expected 1.0", "not to have same value or type as 1"]
  end
end
