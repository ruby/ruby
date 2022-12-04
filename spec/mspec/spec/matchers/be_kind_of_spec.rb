require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BeKindOfMatcher do
  it "matches when actual is a kind_of? expected" do
    expect(BeKindOfMatcher.new(Numeric).matches?(1)).to eq(true)
    expect(BeKindOfMatcher.new(Integer).matches?(2)).to eq(true)
    expect(BeKindOfMatcher.new(Regexp).matches?(/m/)).to eq(true)
  end

  it "does not match when actual is not a kind_of? expected" do
    expect(BeKindOfMatcher.new(Integer).matches?(1.5)).to eq(false)
    expect(BeKindOfMatcher.new(String).matches?(:a)).to eq(false)
    expect(BeKindOfMatcher.new(Hash).matches?([])).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeKindOfMatcher.new(Numeric)
    matcher.matches?('string')
    expect(matcher.failure_message).to eq([
      "Expected \"string\" (String)", "to be kind of Numeric"])
  end

  it "provides a useful negative failure message" do
    matcher = BeKindOfMatcher.new(Numeric)
    matcher.matches?(4.0)
    expect(matcher.negative_failure_message).to eq([
      "Expected 4.0 (Float)", "not to be kind of Numeric"])
  end
end
