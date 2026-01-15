require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe RespondToMatcher do
  it "matches when actual does respond_to? expected" do
    expect(RespondToMatcher.new(:to_s).matches?(Object.new)).to eq(true)
    expect(RespondToMatcher.new(:inject).matches?([])).to eq(true)
    expect(RespondToMatcher.new(:[]).matches?(1)).to eq(true)
    expect(RespondToMatcher.new(:[]=).matches?("string")).to eq(true)
  end

  it "does not match when actual does not respond_to? expected" do
    expect(RespondToMatcher.new(:to_i).matches?(Object.new)).to eq(false)
    expect(RespondToMatcher.new(:inject).matches?(1)).to eq(false)
    expect(RespondToMatcher.new(:non_existent_method).matches?([])).to eq(false)
    expect(RespondToMatcher.new(:[]=).matches?(1)).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = RespondToMatcher.new(:non_existent_method)
    matcher.matches?('string')
    expect(matcher.failure_message).to eq([
      "Expected \"string\" (String)", "to respond to non_existent_method"])
  end

  it "provides a useful negative failure message" do
    matcher = RespondToMatcher.new(:to_i)
    matcher.matches?(4.0)
    expect(matcher.negative_failure_message).to eq([
      "Expected 4.0 (Float)", "not to respond to to_i"])
  end
end
