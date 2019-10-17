# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#start_with?" do
  it "returns true only if beginning match" do
    s = "hello"
    s.should.start_with?('h')
    s.should.start_with?('hel')
    s.should_not.start_with?('el')
  end

  it "returns true only if any beginning match" do
    "hello".should.start_with?('x', 'y', 'he', 'z')
  end

  it "returns true if the search string is empty" do
    "hello".should.start_with?("")
    "".should.start_with?("")
  end

  it "converts its argument using :to_str" do
    s = "hello"
    find = mock('h')
    find.should_receive(:to_str).and_return("h")
    s.should.start_with?(find)
  end

  it "ignores arguments not convertible to string" do
    "hello".should_not.start_with?()
    -> { "hello".start_with?(1) }.should raise_error(TypeError)
    -> { "hello".start_with?(["h"]) }.should raise_error(TypeError)
    -> { "hello".start_with?(1, nil, "h") }.should raise_error(TypeError)
  end

  it "uses only the needed arguments" do
    find = mock('h')
    find.should_not_receive(:to_str)
    "hello".should.start_with?("h",find)
  end

  it "works for multibyte strings" do
    "céréale".should.start_with?("cér")
  end

  ruby_version_is "2.5" do
    it "supports regexps" do
      regexp = /[h1]/
      "hello".should.start_with?(regexp)
      "1337".should.start_with?(regexp)
      "foxes are 1337".should_not.start_with?(regexp)
      "chunky\n12bacon".should_not.start_with?(/12/)
    end

    it "supports regexps with ^ and $ modifiers" do
      regexp1 = /^\d{2}/
      regexp2 = /\d{2}$/
      "12test".should.start_with?(regexp1)
      "test12".should_not.start_with?(regexp1)
      "12test".should_not.start_with?(regexp2)
      "test12".should_not.start_with?(regexp2)
    end

    it "sets Regexp.last_match if it returns true" do
      regexp = /test-(\d+)/
      "test-1337".start_with?(regexp).should be_true
      Regexp.last_match.should_not be_nil
      Regexp.last_match[1].should == "1337"
      $1.should == "1337"

      "test-asdf".start_with?(regexp).should be_false
      Regexp.last_match.should be_nil
      $1.should be_nil
    end
  end
end
