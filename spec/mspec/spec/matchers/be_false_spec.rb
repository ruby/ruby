require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BeFalseMatcher do
  it "matches when actual is false" do
    expect(BeFalseMatcher.new.matches?(false)).to eq(true)
  end

  it "does not match when actual is not false" do
    expect(BeFalseMatcher.new.matches?("")).to eq(false)
    expect(BeFalseMatcher.new.matches?(true)).to eq(false)
    expect(BeFalseMatcher.new.matches?(nil)).to eq(false)
    expect(BeFalseMatcher.new.matches?(0)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeFalseMatcher.new
    matcher.matches?("some string")
    expect(matcher.failure_message).to eq(["Expected \"some string\"", "to be false"])
  end

  it "provides a useful negative failure message" do
    matcher = BeFalseMatcher.new
    matcher.matches?(false)
    expect(matcher.negative_failure_message).to eq(["Expected false", "not to be false"])
  end
end
