require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BeTrueMatcher do
  it "matches when actual is true" do
    expect(BeTrueMatcher.new.matches?(true)).to eq(true)
  end

  it "does not match when actual is not true" do
    expect(BeTrueMatcher.new.matches?("")).to eq(false)
    expect(BeTrueMatcher.new.matches?(false)).to eq(false)
    expect(BeTrueMatcher.new.matches?(nil)).to eq(false)
    expect(BeTrueMatcher.new.matches?(0)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeTrueMatcher.new
    matcher.matches?("some string")
    expect(matcher.failure_message).to eq(["Expected \"some string\"", "to be true"])
  end

  it "provides a useful negative failure message" do
    matcher = BeTrueMatcher.new
    matcher.matches?(true)
    expect(matcher.negative_failure_message).to eq(["Expected true", "not to be true"])
  end
end
