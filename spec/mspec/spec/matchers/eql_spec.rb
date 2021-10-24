require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe EqlMatcher do
  it "matches when actual is eql? to expected" do
    expect(EqlMatcher.new(1).matches?(1)).to eq(true)
    expect(EqlMatcher.new(1.5).matches?(1.5)).to eq(true)
    expect(EqlMatcher.new("red").matches?("red")).to eq(true)
    expect(EqlMatcher.new(:blue).matches?(:blue)).to eq(true)
    expect(EqlMatcher.new(Object).matches?(Object)).to eq(true)

    o = Object.new
    expect(EqlMatcher.new(o).matches?(o)).to eq(true)
  end

  it "does not match when actual is not eql? to expected" do
    expect(EqlMatcher.new(1).matches?(1.0)).to eq(false)
    expect(EqlMatcher.new(Hash).matches?(Object)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = EqlMatcher.new("red")
    matcher.matches?("red")
    expect(matcher.failure_message).to eq(["Expected \"red\"", "to have same value and type as \"red\""])
  end

  it "provides a useful negative failure message" do
    matcher = EqlMatcher.new(1)
    matcher.matches?(1.0)
    expect(matcher.negative_failure_message).to eq(["Expected 1.0", "not to have same value or type as 1"])
  end
end
