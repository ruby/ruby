require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

# Adapted from RSpec 1.0.8
RSpec.describe BeCloseMatcher do
  it "matches when actual == expected" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(5.0)).to eq(true)
  end

  it "matches when actual < (expected + tolerance)" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(5.49)).to eq(true)
  end

  it "matches when actual > (expected - tolerance)" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(4.51)).to eq(true)
  end

  it "matches when actual == (expected + tolerance)" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(5.5)).to eq(true)
    expect(BeCloseMatcher.new(3, 2).matches?(5)).to eq(true)
  end

  it "matches when actual == (expected - tolerance)" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(4.5)).to eq(true)
    expect(BeCloseMatcher.new(3, 2).matches?(1)).to eq(true)
  end

  it "does not match when actual < (expected - tolerance)" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(4.49)).to eq(false)
  end

  it "does not match when actual > (expected + tolerance)" do
    expect(BeCloseMatcher.new(5.0, 0.5).matches?(5.51)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeCloseMatcher.new(5.0, 0.5)
    matcher.matches?(6.5)
    expect(matcher.failure_message).to eq(["Expected 6.5", "to be within 5.0 +/- 0.5"])
  end

  it "provides a useful negative failure message" do
    matcher = BeCloseMatcher.new(5.0, 0.5)
    matcher.matches?(4.9)
    expect(matcher.negative_failure_message).to eq(["Expected 4.9", "not to be within 5.0 +/- 0.5"])
  end
end
