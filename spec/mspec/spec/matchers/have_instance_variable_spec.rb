require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

shared_examples_for "have_instance_variable, on all Ruby versions" do
  after :all do
    Object.const_set :RUBY_VERSION, @ruby_version
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

describe HaveInstanceVariableMatcher, "on RUBY_VERSION >= 1.9" do
  before :all do
    @ruby_version = Object.const_get :RUBY_VERSION
    Object.const_set :RUBY_VERSION, '1.9.0'

    @object = Object.new
    def @object.instance_variables
      [:@foo]
    end
  end

  it_should_behave_like "have_instance_variable, on all Ruby versions"
end
