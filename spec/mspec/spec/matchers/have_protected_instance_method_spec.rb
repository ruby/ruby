require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HPIMMSpecs
  protected

  def protected_method
  end

  class Subclass < HPIMMSpecs
    protected

    def protected_sub_method
    end
  end
end

describe HaveProtectedInstanceMethodMatcher do
  it "inherits from MethodMatcher" do
    HaveProtectedInstanceMethodMatcher.new(:m).should be_kind_of(MethodMatcher)
  end

  it "matches when mod has the protected instance method" do
    matcher = HaveProtectedInstanceMethodMatcher.new :protected_method
    matcher.matches?(HPIMMSpecs).should be_true
    matcher.matches?(HPIMMSpecs::Subclass).should be_true
  end

  it "does not match when mod does not have the protected instance method" do
    matcher = HaveProtectedInstanceMethodMatcher.new :another_method
    matcher.matches?(HPIMMSpecs).should be_false
  end

  it "does not match if the method is in a superclass and include_super is false" do
    matcher = HaveProtectedInstanceMethodMatcher.new :protected_method, false
    matcher.matches?(HPIMMSpecs::Subclass).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HaveProtectedInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    matcher.failure_message.should == [
      "Expected HPIMMSpecs to have protected instance method 'some_method'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveProtectedInstanceMethodMatcher.new :some_method
    matcher.matches?(HPIMMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HPIMMSpecs NOT to have protected instance method 'some_method'",
      "but it does"
    ]
  end
end
