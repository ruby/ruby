require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe IncludeAnyOfMatcher do
  it "matches when actual includes expected" do
    expect(IncludeAnyOfMatcher.new(2).matches?([1,2,3])).to eq(true)
    expect(IncludeAnyOfMatcher.new("b").matches?("abc")).to eq(true)
  end

  it "does not match when actual does not include expected" do
    expect(IncludeAnyOfMatcher.new(4).matches?([1,2,3])).to eq(false)
    expect(IncludeAnyOfMatcher.new("d").matches?("abc")).to eq(false)
  end

  it "matches when actual includes all expected" do
    expect(IncludeAnyOfMatcher.new(3, 2, 1).matches?([1,2,3])).to eq(true)
    expect(IncludeAnyOfMatcher.new("a", "b", "c").matches?("abc")).to eq(true)
  end

  it "matches when actual includes any expected" do
    expect(IncludeAnyOfMatcher.new(3, 4, 5).matches?([1,2,3])).to eq(true)
    expect(IncludeAnyOfMatcher.new("c", "d", "e").matches?("abc")).to eq(true)
  end

  it "does not match when actual does not include any expected" do
    expect(IncludeAnyOfMatcher.new(4, 5).matches?([1,2,3])).to eq(false)
    expect(IncludeAnyOfMatcher.new("de").matches?("abc")).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = IncludeAnyOfMatcher.new(5, 6)
    matcher.matches?([1,2,3])
    expect(matcher.failure_message).to eq(["Expected [1, 2, 3]", "to include any of [5, 6]"])
  end

  it "provides a useful negative failure message" do
    matcher = IncludeAnyOfMatcher.new(1, 2, 3)
    matcher.matches?([1,2])
    expect(matcher.negative_failure_message).to eq(["Expected [1, 2]", "not to include any of [1, 2, 3]"])
  end
end
