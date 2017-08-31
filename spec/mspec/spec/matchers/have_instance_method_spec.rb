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

describe HaveInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    HaveInstanceMethodMatcher.new(:m).should be_kind_of(MethodMatcher)
  end

  it "matches when mod has the instance method" do
    matcher = HaveInstanceMethodMatcher.new :instance_method
    matcher.matches?(HIMMSpecs).should be_true
    matcher.matches?(HIMMSpecs::Subclass).should be_true
  end

  it "does not match when mod does not have the instance method" do
    matcher = HaveInstanceMethodMatcher.new :another_method
    matcher.matches?(HIMMSpecs).should be_false
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HaveInstanceMethodMatcher.new :instance_method, false
    matcher.matches?(HIMMSpecs::Subclass).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HaveInstanceMethodMatcher.new :some_method
    matcher.matches?(HIMMSpecs)
    matcher.failure_message.should == [
      "Expected HIMMSpecs to have instance method 'some_method'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveInstanceMethodMatcher.new :some_method
    matcher.matches?(HIMMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HIMMSpecs NOT to have instance method 'some_method'",
      "but it does"
    ]
  end
end
