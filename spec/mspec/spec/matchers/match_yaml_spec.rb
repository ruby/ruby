require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe MatchYAMLMatcher do
  before :each do
    @matcher = MatchYAMLMatcher.new("--- \nfoo: bar\n")
  end

  it "compares YAML documents and matches if they're equivalent" do
      expect(@matcher.matches?("--- \nfoo: bar\n")).to eq(true)
  end

  it "compares YAML documents and does not match if they're not equivalent" do
      expect(@matcher.matches?("--- \nbar: foo\n")).to eq(false)
      expect(@matcher.matches?("--- \nfoo: \nbar\n")).to eq(false)
  end

  it "also receives objects that respond_to to_yaml" do
    matcher = MatchYAMLMatcher.new("some string")
    expect(matcher.matches?("some string")).to eq(true)

    matcher = MatchYAMLMatcher.new(['a', 'b'])
    expect(matcher.matches?("--- \n- a\n- b\n")).to eq(true)

    matcher = MatchYAMLMatcher.new("foo" => "bar")
    expect(matcher.matches?("--- \nfoo: bar\n")).to eq(true)
  end

  it "matches documents with trailing whitespace" do
    expect(@matcher.matches?("--- \nfoo: bar   \n")).to eq(true)
    expect(@matcher.matches?("---       \nfoo: bar   \n")).to eq(true)
  end

  it "fails with a descriptive error message" do
    expect(@matcher.matches?("foo")).to eq(false)
    expect(@matcher.failure_message).to eq(["Expected \"foo\"", " to match \"--- \\nfoo: bar\\n\""])
  end
end
