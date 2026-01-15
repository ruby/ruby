require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/guards'
require 'mspec/helpers'
require 'mspec/matchers'

RSpec.describe InfinityMatcher do
  it "matches when actual is infinite and has the correct sign" do
    expect(InfinityMatcher.new(1).matches?(infinity_value)).to eq(true)
    expect(InfinityMatcher.new(-1).matches?(-infinity_value)).to eq(true)
  end

  it "does not match when actual is not infinite" do
    expect(InfinityMatcher.new(1).matches?(1.0)).to eq(false)
    expect(InfinityMatcher.new(-1).matches?(-1.0)).to eq(false)
  end

  it "does not match when actual is infinite but has the incorrect sign" do
    expect(InfinityMatcher.new(1).matches?(-infinity_value)).to eq(false)
    expect(InfinityMatcher.new(-1).matches?(infinity_value)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = InfinityMatcher.new(-1)
    matcher.matches?(0)
    expect(matcher.failure_message).to eq(["Expected 0", "to be -Infinity"])
  end

  it "provides a useful negative failure message" do
    matcher = InfinityMatcher.new(1)
    matcher.matches?(infinity_value)
    expect(matcher.negative_failure_message).to eq(["Expected Infinity", "not to be Infinity"])
  end
end
