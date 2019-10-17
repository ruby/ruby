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

describe BeAnInstanceOfMatcher do
  it "matches when actual is an instance_of? expected" do
    a = BeAnInOfSpecs::A.new
    BeAnInstanceOfMatcher.new(BeAnInOfSpecs::A).matches?(a).should be_true

    b = BeAnInOfSpecs::B.new
    BeAnInstanceOfMatcher.new(BeAnInOfSpecs::B).matches?(b).should be_true
  end

  it "does not match when actual is not an instance_of? expected" do
    a = BeAnInOfSpecs::A.new
    BeAnInstanceOfMatcher.new(BeAnInOfSpecs::B).matches?(a).should be_false

    b = BeAnInOfSpecs::B.new
    BeAnInstanceOfMatcher.new(BeAnInOfSpecs::A).matches?(b).should be_false

    c = BeAnInOfSpecs::C.new
    BeAnInstanceOfMatcher.new(BeAnInOfSpecs::A).matches?(c).should be_false
    BeAnInstanceOfMatcher.new(BeAnInOfSpecs::B).matches?(c).should be_false
  end

  it "provides a useful failure message" do
    matcher = BeAnInstanceOfMatcher.new(Numeric)
    matcher.matches?("string")
    matcher.failure_message.should == [
      "Expected \"string\" (String)", "to be an instance of Numeric"]
  end

  it "provides a useful negative failure message" do
    matcher = BeAnInstanceOfMatcher.new(Numeric)
    matcher.matches?(4.0)
    matcher.negative_failure_message.should == [
      "Expected 4.0 (Float)", "not to be an instance of Numeric"]
  end
end
