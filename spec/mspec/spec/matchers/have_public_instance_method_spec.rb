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

describe HavePublicInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    HavePublicInstanceMethodMatcher.new(:m).should be_kind_of(MethodMatcher)
  end

  it "matches when mod has the public instance method" do
    matcher = HavePublicInstanceMethodMatcher.new :public_method
    matcher.matches?(HPIMMSpecs).should be_true
    matcher.matches?(HPIMMSpecs::Subclass).should be_true
  end

  it "does not match when mod does not have the public instance method" do
    matcher = HavePublicInstanceMethodMatcher.new :another_method
    matcher.matches?(HPIMMSpecs).should be_false
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HavePublicInstanceMethodMatcher.new :public_method, false
    matcher.matches?(HPIMMSpecs::Subclass).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HavePublicInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    matcher.failure_message.should == [
      "Expected HPIMMSpecs to have public instance method 'some_method'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HavePublicInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HPIMMSpecs NOT to have public instance method 'some_method'",
      "but it does"
    ]
  end
end
