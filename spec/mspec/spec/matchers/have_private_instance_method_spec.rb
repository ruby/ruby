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

describe HavePrivateInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    HavePrivateInstanceMethodMatcher.new(:m).should be_kind_of(MethodMatcher)
  end

  it "matches when mod has the private instance method" do
    matcher = HavePrivateInstanceMethodMatcher.new :private_method
    matcher.matches?(HPIMMSpecs).should be_true
    matcher.matches?(HPIMMSpecs::Subclass).should be_true
  end

  it "does not match when mod does not have the private instance method" do
    matcher = HavePrivateInstanceMethodMatcher.new :another_method
    matcher.matches?(HPIMMSpecs).should be_false
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HavePrivateInstanceMethodMatcher.new :private_method, false
    matcher.matches?(HPIMMSpecs::Subclass).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HavePrivateInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    matcher.failure_message.should == [
      "Expected HPIMMSpecs to have private instance method 'some_method'",
      "but it does not"
    ]
  end

  it "provides a failure message for #should_not" do
    matcher = HavePrivateInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HPIMMSpecs NOT to have private instance method 'some_method'",
      "but it does"
    ]
  end
end
