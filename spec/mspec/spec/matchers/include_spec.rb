require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe IncludeMatcher do
  it "matches when actual includes expected" do
    expect(IncludeMatcher.new(2).matches?([1,2,3])).to eq(true)
    expect(IncludeMatcher.new("b").matches?("abc")).to eq(true)
  end

  it "does not match when actual does not include expected" do
    expect(IncludeMatcher.new(4).matches?([1,2,3])).to eq(false)
    expect(IncludeMatcher.new("d").matches?("abc")).to eq(false)
  end

  it "matches when actual includes all expected" do
    expect(IncludeMatcher.new(3, 2, 1).matches?([1,2,3])).to eq(true)
    expect(IncludeMatcher.new("a", "b", "c").matches?("abc")).to eq(true)
  end

  it "does not match when actual does not include all expected" do
    expect(IncludeMatcher.new(3, 2, 4).matches?([1,2,3])).to eq(false)
    expect(IncludeMatcher.new("a", "b", "c", "d").matches?("abc")).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = IncludeMatcher.new(5, 2)
    matcher.matches?([1,2,3])
    expect(matcher.failure_message).to eq(["Expected [1, 2, 3]", "to include 5"])
  end

  it "provides a useful negative failure message" do
    matcher = IncludeMatcher.new(1, 2, 3)
    matcher.matches?([1,2,3])
    expect(matcher.negative_failure_message).to eq(["Expected [1, 2, 3]", "not to include 3"])
  end
end
