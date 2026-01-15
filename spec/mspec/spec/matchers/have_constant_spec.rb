require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class HCMSpecs
  X = :x
end

RSpec.describe HaveConstantMatcher do
  it "matches when mod has the constant" do
    matcher = HaveConstantMatcher.new :X
    expect(matcher.matches?(HCMSpecs)).to be_truthy
  end

  it "does not match when mod does not have the constant" do
    matcher = HaveConstantMatcher.new :A
    expect(matcher.matches?(HCMSpecs)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HaveConstantMatcher.new :A
    matcher.matches?(HCMSpecs)
    expect(matcher.failure_message).to eq([
      "Expected HCMSpecs to have constant 'A'",
      "but it does not"
    ])
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveConstantMatcher.new :X
    matcher.matches?(HCMSpecs)
    expect(matcher.negative_failure_message).to eq([
      "Expected HCMSpecs NOT to have constant 'X'",
      "but it does"
    ])
  end
end
