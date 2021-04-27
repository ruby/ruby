require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe BeTrueOrFalseMatcher do
  it "matches when actual is true" do
    expect(BeTrueOrFalseMatcher.new.matches?(true)).to eq(true)
  end

  it "matches when actual is false" do
    expect(BeTrueOrFalseMatcher.new.matches?(false)).to eq(true)
  end

  it "provides a useful failure message" do
    matcher = BeTrueOrFalseMatcher.new
    matcher.matches?("some string")
    expect(matcher.failure_message).to eq(["Expected \"some string\"", "to be true or false"])
  end
end
