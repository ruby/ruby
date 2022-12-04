require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HIMMSpecs
  def instance_method
  end

  class Subclass < HIMMSpecs
    def instance_sub_method
    end
  end
end

RSpec.describe HaveInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    expect(HaveInstanceMethodMatcher.new(:m)).to be_kind_of(MethodMatcher)
  end

  it "matches when mod has the instance method" do
    matcher = HaveInstanceMethodMatcher.new :instance_method
    expect(matcher.matches?(HIMMSpecs)).to be_truthy
    expect(matcher.matches?(HIMMSpecs::Subclass)).to be_truthy
  end

  it "does not match when mod does not have the instance method" do
    matcher = HaveInstanceMethodMatcher.new :another_method
    expect(matcher.matches?(HIMMSpecs)).to be_falsey
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HaveInstanceMethodMatcher.new :instance_method, false
    expect(matcher.matches?(HIMMSpecs::Subclass)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HaveInstanceMethodMatcher.new :some_method
    matcher.matches?(HIMMSpecs)
    expect(matcher.failure_message).to eq([
      "Expected HIMMSpecs to have instance method 'some_method'",
      "but it does not"
    ])
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveInstanceMethodMatcher.new :some_method
    matcher.matches?(HIMMSpecs)
    expect(matcher.negative_failure_message).to eq([
      "Expected HIMMSpecs NOT to have instance method 'some_method'",
      "but it does"
    ])
  end
end
