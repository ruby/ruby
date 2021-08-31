require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HPIMMSpecs
  private

  def private_method
  end

  class Subclass < HPIMMSpecs
    private

    def private_sub_method
    end
  end
end

RSpec.describe HavePrivateInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    expect(HavePrivateInstanceMethodMatcher.new(:m)).to be_kind_of(MethodMatcher)
  end

  it "matches when mod has the private instance method" do
    matcher = HavePrivateInstanceMethodMatcher.new :private_method
    expect(matcher.matches?(HPIMMSpecs)).to be_truthy
    expect(matcher.matches?(HPIMMSpecs::Subclass)).to be_truthy
  end

  it "does not match when mod does not have the private instance method" do
    matcher = HavePrivateInstanceMethodMatcher.new :another_method
    expect(matcher.matches?(HPIMMSpecs)).to be_falsey
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HavePrivateInstanceMethodMatcher.new :private_method, false
    expect(matcher.matches?(HPIMMSpecs::Subclass)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HavePrivateInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    expect(matcher.failure_message).to eq([
      "Expected HPIMMSpecs to have private instance method 'some_method'",
      "but it does not"
    ])
  end

  it "provides a failure message for #should_not" do
    matcher = HavePrivateInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    expect(matcher.negative_failure_message).to eq([
      "Expected HPIMMSpecs NOT to have private instance method 'some_method'",
      "but it does"
    ])
  end
end
