require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HMMSpecs
  def instance_method
  end

  class Subclass < HMMSpecs
    def instance_sub_method
    end
  end
end

RSpec.describe HaveMethodMatcher do
  it "inherits from MethodMatcher" do
    expect(HaveMethodMatcher.new(:m)).to be_kind_of(MethodMatcher)
  end

  it "matches when mod has the method" do
    matcher = HaveMethodMatcher.new :instance_method
    expect(matcher.matches?(HMMSpecs)).to be_truthy
    expect(matcher.matches?(HMMSpecs.new)).to be_truthy
    expect(matcher.matches?(HMMSpecs::Subclass)).to be_truthy
    expect(matcher.matches?(HMMSpecs::Subclass.new)).to be_truthy
  end

  it "does not match when mod does not have the method" do
    matcher = HaveMethodMatcher.new :another_method
    expect(matcher.matches?(HMMSpecs)).to be_falsey
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HaveMethodMatcher.new :instance_method, false
    expect(matcher.matches?(HMMSpecs::Subclass)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HaveMethodMatcher.new :some_method
    matcher.matches?(HMMSpecs)
    expect(matcher.failure_message).to eq([
      "Expected HMMSpecs to have method 'some_method'",
      "but it does not"
    ])
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveMethodMatcher.new :some_method
    matcher.matches?(HMMSpecs)
    expect(matcher.negative_failure_message).to eq([
      "Expected HMMSpecs NOT to have method 'some_method'",
      "but it does"
    ])
  end
end
