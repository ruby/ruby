require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class IVarModMock; end

shared_examples_for "have_class_variable, on all Ruby versions" do
  after :all do
    Object.const_set :RUBY_VERSION, @ruby_version
  end

  it "matches when mod has the class variable, given as string" do
    matcher = HaveClassVariableMatcher.new('@foo')
    matcher.matches?(IVarModMock).should be_true
  end

  it "matches when mod has the class variable, given as symbol" do
    matcher = HaveClassVariableMatcher.new(:@foo)
    matcher.matches?(IVarModMock).should be_true
  end

  it "does not match when mod hasn't got the class variable, given as string" do
    matcher = HaveClassVariableMatcher.new('@bar')
    matcher.matches?(IVarModMock).should be_false
  end

  it "does not match when mod hasn't got the class variable, given as symbol" do
    matcher = HaveClassVariableMatcher.new(:@bar)
    matcher.matches?(IVarModMock).should be_false
  end

  it "provides a failure message for #should" do
    matcher = HaveClassVariableMatcher.new(:@bar)
    matcher.matches?(IVarModMock)
    matcher.failure_message.should == [
      "Expected IVarModMock to have class variable '@bar'",
      "but it does not"
    ]
  end

  it "provides a failure messoge for #should_not" do
    matcher = HaveClassVariableMatcher.new(:@bar)
    matcher.matches?(IVarModMock)
    matcher.negative_failure_message.should == [
      "Expected IVarModMock NOT to have class variable '@bar'",
      "but it does"
    ]
  end
end

describe HaveClassVariableMatcher, "on RUBY_VERSION >= 1.9" do
  before :all do
    @ruby_version = Object.const_get :RUBY_VERSION
    Object.const_set :RUBY_VERSION, '1.9.0'

    def IVarModMock.class_variables
      [:@foo]
    end
  end

  it_should_behave_like "have_class_variable, on all Ruby versions"
end
