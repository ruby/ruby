require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe HaveInstanceVariableMatcher do
  before :each do
    @object = Object.new
    def @object.instance_variables
      [:@foo]
    end
  end

  it "matches when object has the instance variable, given as string" do
    matcher = HaveInstanceVariableMatcher.new('@foo')
    matcher.matches?(@object).should be_true
  end

  it "matches when object has the instance variable, given as symbol" do
    matcher = HaveInstanceVariableMatcher.new(:@foo)
    matcher.matches?(@object).should be_true
  end

  it "does not match when object hasn't got the instance variable, given as string" do
    matcher = HaveInstanceVariableMatcher.new('@bar')
    matcher.matches?(@object).should be_false
  end

  it "does not match when object hasn't got the instance variable, given as symbol" do
    matcher = HaveInstanceVariableMatcher.new(:@bar)
    matcher.matches?(@object).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HaveInstanceVariableMatcher.new(:@bar)
    matcher.matches?(@object)
    matcher.failure_message.should == [
      "Expected #{@object.inspect} to have instance variable '@bar'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveInstanceVariableMatcher.new(:@bar)
    matcher.matches?(@object)
    matcher.negative_failure_message.should == [
      "Expected #{@object.inspect} NOT to have instance variable '@bar'",
      "but it does"
    ]
  end
end
