require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BeNilMatcher do
  it "matches when actual is nil" do
    expect(BeNilMatcher.new.matches?(nil)).to eq(true)
  end

  it "does not match when actual is not nil" do
    expect(BeNilMatcher.new.matches?("")).to eq(false)
    expect(BeNilMatcher.new.matches?(false)).to eq(false)
    expect(BeNilMatcher.new.matches?(0)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeNilMatcher.new
    matcher.matches?("some string")
    expect(matcher.failure_message).to eq(["Expected \"some string\"", "to be nil"])
  end

  it "provides a useful negative failure message" do
    matcher = BeNilMatcher.new
    matcher.matches?(nil)
    expect(matcher.negative_failure_message).to eq(["Expected nil", "not to be nil"])
  end
end
