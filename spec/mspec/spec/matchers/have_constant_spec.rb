require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HCMSpecs
  X = :x
end

describe HaveConstantMatcher do
  it "matches when mod has the constant" do
    matcher = HaveConstantMatcher.new :X
    matcher.matches?(HCMSpecs).should be_true
  end

  it "does not match when mod does not have the constant" do
    matcher = HaveConstantMatcher.new :A
    matcher.matches?(HCMSpecs).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HaveConstantMatcher.new :A
    matcher.matches?(HCMSpecs)
    matcher.failure_message.should == [
      "Expected HCMSpecs to have constant 'A'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveConstantMatcher.new :X
    matcher.matches?(HCMSpecs)
    matcher.negative_failure_message.should == [
      "Expected HCMSpecs NOT to have constant 'X'",
      "but it does"
    ]
  end
end
