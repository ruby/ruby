require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe HaveInstanceVariableMatcher do
  before :each do
    @object = Object.new
    def @object.instance_variables
      [:@foo]
    end
  end

  it "matches when object has the instance variable, given as string" do
    matcher = HaveInstanceVariableMatcher.new('@foo')
    expect(matcher.matches?(@object)).to be_truthy
  end

  it "matches when object has the instance variable, given as symbol" do
    matcher = HaveInstanceVariableMatcher.new(:@foo)
    expect(matcher.matches?(@object)).to be_truthy
  end

  it "does not match when object hasn't got the instance variable, given as string" do
    matcher = HaveInstanceVariableMatcher.new('@bar')
    expect(matcher.matches?(@object)).to be_falsey
  end

  it "does not match when object hasn't got the instance variable, given as symbol" do
    matcher = HaveInstanceVariableMatcher.new(:@bar)
    expect(matcher.matches?(@object)).to be_falsey
  end

  it "provides a failure message for #should" do
    matcher = HaveInstanceVariableMatcher.new(:@bar)
    matcher.matches?(@object)
    expect(matcher.failure_message).to eq([
      "Expected #{@object.inspect} to have instance variable '@bar'",
      "but it does not"
    ])
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveInstanceVariableMatcher.new(:@bar)
    matcher.matches?(@object)
    expect(matcher.negative_failure_message).to eq([
      "Expected #{@object.inspect} NOT to have instance variable '@bar'",
      "but it does"
    ])
  end
end
