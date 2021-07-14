require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

module BeAnInOfSpecs
  class A
  end

  class B < A
  end

  class C < B
  end
end

RSpec.describe BeAnInstanceOfMatcher do
  it "matches when actual is an instance_of? expected" do
    a = BeAnInOfSpecs::A.new
    expect(BeAnInstanceOfMatcher.new(BeAnInOfSpecs::A).matches?(a)).to be_truthy

    b = BeAnInOfSpecs::B.new
    expect(BeAnInstanceOfMatcher.new(BeAnInOfSpecs::B).matches?(b)).to be_truthy
  end

  it "does not match when actual is not an instance_of? expected" do
    a = BeAnInOfSpecs::A.new
    expect(BeAnInstanceOfMatcher.new(BeAnInOfSpecs::B).matches?(a)).to be_falsey

    b = BeAnInOfSpecs::B.new
    expect(BeAnInstanceOfMatcher.new(BeAnInOfSpecs::A).matches?(b)).to be_falsey

    c = BeAnInOfSpecs::C.new
    expect(BeAnInstanceOfMatcher.new(BeAnInOfSpecs::A).matches?(c)).to be_falsey
    expect(BeAnInstanceOfMatcher.new(BeAnInOfSpecs::B).matches?(c)).to be_falsey
  end

  it "provides a useful failure message" do
    matcher = BeAnInstanceOfMatcher.new(Numeric)
    matcher.matches?("string")
    expect(matcher.failure_message).to eq([
      "Expected \"string\" (String)", "to be an instance of Numeric"])
  end

  it "provides a useful negative failure message" do
    matcher = BeAnInstanceOfMatcher.new(Numeric)
    matcher.matches?(4.0)
    expect(matcher.negative_failure_message).to eq([
      "Expected 4.0 (Float)", "not to be an instance of Numeric"])
  end
end
