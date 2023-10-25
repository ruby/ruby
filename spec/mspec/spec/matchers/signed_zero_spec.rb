require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe SignedZeroMatcher do
  it "matches when actual is zero and has the correct sign" do
    expect(SignedZeroMatcher.new(1).matches?(0.0)).to eq(true)
    expect(SignedZeroMatcher.new(-1).matches?(-0.0)).to eq(true)
  end

  it "does not match when actual is non-zero" do
    expect(SignedZeroMatcher.new(1).matches?(1.0)).to eq(false)
    expect(SignedZeroMatcher.new(-1).matches?(-1.0)).to eq(false)
  end

  it "does not match when actual is zero but has the incorrect sign" do
    expect(SignedZeroMatcher.new(1).matches?(-0.0)).to eq(false)
    expect(SignedZeroMatcher.new(-1).matches?(0.0)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = SignedZeroMatcher.new(-1)
    matcher.matches?(0.0)
    expect(matcher.failure_message).to eq(["Expected 0.0", "to be -0.0"])
  end

  it "provides a useful negative failure message" do
    matcher = SignedZeroMatcher.new(-1)
    matcher.matches?(-0.0)
    expect(matcher.negative_failure_message).to eq(["Expected -0.0", "not to be -0.0"])
  end
end
