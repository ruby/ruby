require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe MatchYAMLMatcher do
  before :each do
    @matcher = MatchYAMLMatcher.new("--- \nfoo: bar\n")
  end

  it "compares YAML documents and matches if they're equivalent" do
      @matcher.matches?("--- \nfoo: bar\n").should == true
  end

  it "compares YAML documents and does not match if they're not equivalent" do
      @matcher.matches?("--- \nbar: foo\n").should == false
      @matcher.matches?("--- \nfoo: \nbar\n").should == false
  end

  it "also receives objects that respond_to to_yaml" do
    matcher = MatchYAMLMatcher.new("some string")
    matcher.matches?("some string").should == true

    matcher = MatchYAMLMatcher.new(['a', 'b'])
    matcher.matches?("--- \n- a\n- b\n").should == true

    matcher = MatchYAMLMatcher.new("foo" => "bar")
    matcher.matches?("--- \nfoo: bar\n").should == true
  end

  it "matches documents with trailing whitespace" do
    @matcher.matches?("--- \nfoo: bar   \n").should == true
    @matcher.matches?("---       \nfoo: bar   \n").should == true
  end

  it "fails with a descriptive error message" do
    @matcher.matches?("foo").should == false
    @matcher.failure_message.should == ["Expected \"foo\"", " to match \"--- \\nfoo: bar\\n\""]
  end
end
