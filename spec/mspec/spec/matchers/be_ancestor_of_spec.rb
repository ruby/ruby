require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class Parent; end
class Child < Parent; end

describe BeAncestorOfMatcher do
  it "matches when actual is an ancestor of expected" do
    BeAncestorOfMatcher.new(Child).matches?(Parent).should == true
  end

  it "does not match when actual is not an ancestor of expected" do
    BeAncestorOfMatcher.new(Parent).matches?(Child).should == false
  end

  it "provides a useful failure message" do
    matcher = BeAncestorOfMatcher.new(Parent)
    matcher.matches?(Child)
    matcher.failure_message.should == ["Expected Child", "to be an ancestor of Parent"]
  end

  it "provides a useful negative failure message" do
    matcher = BeAncestorOfMatcher.new(Child)
    matcher.matches?(Parent)
    matcher.negative_failure_message.should == ["Expected Parent", "not to be an ancestor of Child"]
  end
end
