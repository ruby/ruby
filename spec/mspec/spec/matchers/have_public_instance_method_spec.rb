require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HPIMMSpecs
  def public_method
  end

  class Subclass < HPIMMSpecs
    def public_sub_method
    end
  end
end

RSpec.describe HavePublicInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    expect(HavePublicInstanceMethodMatcher.new(:m)).to be_kind_of(MethodMatcher)
  end

  it "matches when mod has the public instance method" do
    matcher = HavePublicInstanceMethodMatcher.new :public_method
    expect(matcher.matches?(HPIMMSpecs)).to be_truthy
    expect(matcher.matches?(HPIMMSpecs::Subclass)).to be_truthy
  end

  it "does not match when mod does not have the public instance method" do
    matcher = HavePublicInstanceMethodMatcher.new :another_method
    expect(matcher.matches?(HPIMMSpecs)).to be_falsey
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HavePublicInstanceMethodMatcher.new :public_method, false
    expect(matcher.matches?(HPIMMSpecs::Subclass)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HavePublicInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    expect(matcher.failure_message).to eq([
      "Expected HPIMMSpecs to have public instance method 'some_method'",
      "but it does not"
    ])
  end

  it "provides a failure messoge for #should_not" do
    matcher = HavePublicInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    expect(matcher.negative_failure_message).to eq([
      "Expected HPIMMSpecs NOT to have public instance method 'some_method'",
      "but it does"
    ])
  end
end
