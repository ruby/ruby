require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe EqualMatcher do
  it "matches when actual is equal? to expected" do
    expect(EqualMatcher.new(1).matches?(1)).to eq(true)
    expect(EqualMatcher.new(:blue).matches?(:blue)).to eq(true)
    expect(EqualMatcher.new(Object).matches?(Object)).to eq(true)

    o = Object.new
    expect(EqualMatcher.new(o).matches?(o)).to eq(true)
  end

  it "does not match when actual is not a equal? to expected" do
    expect(EqualMatcher.new(1).matches?(1.0)).to eq(false)
    expect(EqualMatcher.new("blue").matches?("blue")).to eq(false)
    expect(EqualMatcher.new(Hash).matches?(Object)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = EqualMatcher.new("red")
    matcher.matches?("red")
    expect(matcher.failure_message).to eq(["Expected \"red\"", "to be identical to \"red\""])
  end

  it "provides a useful negative failure message" do
    matcher = EqualMatcher.new(1)
    matcher.matches?(1)
    expect(matcher.negative_failure_message).to eq(["Expected 1", "not to be identical to 1"])
  end
end
