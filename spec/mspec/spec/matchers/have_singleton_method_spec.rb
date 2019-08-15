require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HSMMSpecs
  def self.singleton_method
  end
end

describe HaveSingletonMethodMatcher do
  it "inherits from MethodMatcher" do
    HaveSingletonMethodMatcher.new(:m).should be_kind_of(MethodMatcher)
  end

  it "matches when the class has a singleton method" do
    matcher = HaveSingletonMethodMatcher.new :singleton_method
    matcher.matches?(HSMMSpecs).should be_true
  end

  it "matches when the object has a singleton method" do
    obj = double("HSMMSpecs")
    def obj.singleton_method; end

    matcher = HaveSingletonMethodMatcher.new :singleton_method
    matcher.matches?(obj).should be_true
  end

  it "provides a failure message for #should" do
    matcher = HaveSingletonMethodMatcher.new :some_method
    matcher.matches?(HSMMSpecs)
    matcher.failure_message.should == [
      "Expected HSMMSpecs to have singleton method 'some_method'",
      "but it does not"
    ]
  end

  it "provides a failure message for #should_not" do
    matcher = HaveSingletonMethodMatcher.new :singleton_method
    matcher.matches?(HSMMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HSMMSpecs NOT to have singleton method 'singleton_method'",
      "but it does"
    ]
  end
end
