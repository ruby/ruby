require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HPMMSpecs
  def self.private_method
  end

  private_class_method :private_method
end

RSpec.describe HavePrivateMethodMatcher do
  it "inherits from MethodMatcher" do
    expect(HavePrivateMethodMatcher.new(:m)).to be_kind_of(MethodMatcher)
  end

  it "matches when mod has the private method" do
    matcher = HavePrivateMethodMatcher.new :private_method
    expect(matcher.matches?(HPMMSpecs)).to be_truthy
  end

  it "does not match when mod does not have the private method" do
    matcher = HavePrivateMethodMatcher.new :another_method
    expect(matcher.matches?(HPMMSpecs)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HavePrivateMethodMatcher.new :some_method
    matcher.matches?(HPMMSpecs)
    expect(matcher.failure_message).to eq([
      "Expected HPMMSpecs to have private method 'some_method'",
      "but it does not"
    ])
  end

  it "provides a failure message for #should_not" do
    matcher = HavePrivateMethodMatcher.new :private_method
    matcher.matches?(HPMMSpecs)
    expect(matcher.negative_failure_message).to eq([
      "Expected HPMMSpecs NOT to have private method 'private_method'",
      "but it does"
    ])
  end
end
