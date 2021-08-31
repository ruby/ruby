require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/guards'
require 'mspec/helpers'
require 'mspec/matchers'

RSpec.describe BeNaNMatcher do
  it "matches when actual is NaN" do
    expect(BeNaNMatcher.new.matches?(nan_value)).to eq(true)
  end

  it "does not match when actual is not NaN" do
    expect(BeNaNMatcher.new.matches?(1.0)).to eq(false)
    expect(BeNaNMatcher.new.matches?(0)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeNaNMatcher.new
    matcher.matches?(0)
    expect(matcher.failure_message).to eq(["Expected 0", "to be NaN"])
  end

  it "provides a useful negative failure message" do
    matcher = BeNaNMatcher.new
    matcher.matches?(nan_value)
    expect(matcher.negative_failure_message).to eq(["Expected NaN", "not to be NaN"])
  end
end
