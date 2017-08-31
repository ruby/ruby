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

describe HaveMethodMatcher do
  it "inherits from MethodMatcher" do
    HaveMethodMatcher.new(:m).should be_kind_of(MethodMatcher)
  end

  it "matches when mod has the method" do
    matcher = HaveMethodMatcher.new :instance_method
    matcher.matches?(HMMSpecs).should be_true
    matcher.matches?(HMMSpecs.new).should be_true
    matcher.matches?(HMMSpecs::Subclass).should be_true
    matcher.matches?(HMMSpecs::Subclass.new).should be_true
  end

  it "does not match when mod does not have the method" do
    matcher = HaveMethodMatcher.new :another_method
    matcher.matches?(HMMSpecs).should be_false
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HaveMethodMatcher.new :instance_method, false
    matcher.matches?(HMMSpecs::Subclass).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HaveMethodMatcher.new :some_method
    matcher.matches?(HMMSpecs)
    matcher.failure_message.should == [
      "Expected HMMSpecs to have method 'some_method'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveMethodMatcher.new :some_method
    matcher.matches?(HMMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HMMSpecs NOT to have method 'some_method'",
      "but it does"
    ]
  end
end
