require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BeEmptyMatcher do
  it "matches when actual is empty" do
    expect(BeEmptyMatcher.new.matches?("")).to eq(true)
  end

  it "does not match when actual is not empty" do
    expect(BeEmptyMatcher.new.matches?([10])).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = BeEmptyMatcher.new
    matcher.matches?("not empty string")
    expect(matcher.failure_message).to eq(["Expected \"not empty string\"", "to be empty"])
  end

  it "provides a useful negative failure message" do
    matcher = BeEmptyMatcher.new
    matcher.matches?("")
    expect(matcher.negative_failure_message).to eq(["Expected \"\"", "not to be empty"])
  end
end

