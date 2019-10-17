require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe BeTrueOrFalseMatcher do
  it "matches when actual is true" do
    BeTrueOrFalseMatcher.new.matches?(true).should == true
  end

  it "matches when actual is false" do
    BeTrueOrFalseMatcher.new.matches?(false).should == true
  end

  it "provides a useful failure message" do
    matcher = BeTrueOrFalseMatcher.new
    matcher.matches?("some string")
    matcher.failure_message.should == ["Expected \"some string\"", "to be true or false"]
  end
end
