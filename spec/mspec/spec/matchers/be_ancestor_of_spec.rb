require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class Parent; end
class Child < Parent; end

RSpec.describe BeAncestorOfMatcher do
  it "matches when actual is an ancestor of expected" do
    expect(BeAncestorOfMatcher.new(Child).matches?(Parent)).to eq(true)
  end

  it "does not match when actual is not an ancestor of expected" do
    expect(BeAncestorOfMatcher.new(Parent).matches?(Child)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeAncestorOfMatcher.new(Parent)
    matcher.matches?(Child)
    expect(matcher.failure_message).to eq(["Expected Child", "to be an ancestor of Parent"])
  end

  it "provides a useful negative failure message" do
    matcher = BeAncestorOfMatcher.new(Child)
    matcher.matches?(Parent)
    expect(matcher.negative_failure_message).to eq(["Expected Parent", "not to be an ancestor of Child"])
  end
end
