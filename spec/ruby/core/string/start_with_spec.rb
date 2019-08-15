# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "String#start_with?" do
  it "returns true only if beginning match" do
    s = "hello"
    s.start_with?('h').should be_true
    s.start_with?('hel').should be_true
    s.start_with?('el').should be_false
  end

  it "returns true only if any beginning match" do
    "hello".start_with?('x', 'y', 'he', 'z').should be_true
  end

  it "returns true if the search string is empty" do
    "hello".start_with?("").should be_true
    "".start_with?("").should be_true
  end

  it "converts its argument using :to_str" do
    s = "hello"
    find = mock('h')
    find.should_receive(:to_str).and_return("h")
    s.start_with?(find).should be_true
  end

  it "ignores arguments not convertible to string" do
    "hello".start_with?().should be_false
    -> { "hello".start_with?(1) }.should raise_error(TypeError)
    -> { "hello".start_with?(["h"]) }.should raise_error(TypeError)
    -> { "hello".start_with?(1, nil, "h") }.should raise_error(TypeError)
  end

  it "uses only the needed arguments" do
    find = mock('h')
    find.should_not_receive(:to_str)
    "hello".start_with?("h",find).should be_true
  end

  it "works for multibyte strings" do
    "céréale".start_with?("cér").should be_true
  end

  ruby_version_is "2.5" do
    it "supports regexps" do
      regexp = /[h1]/
      "hello".start_with?(regexp).should be_true
      "1337".start_with?(regexp).should be_true
      "foxes are 1337".start_with?(regexp).should be_false
      "chunky\n12bacon".start_with?(/12/).should be_false
    end

    it "supports regexps with ^ and $ modifiers" do
      regexp1 = /^\d{2}/
      regexp2 = /\d{2}$/
      "12test".start_with?(regexp1).should be_true
      "test12".start_with?(regexp1).should be_false
      "12test".start_with?(regexp2).should be_false
      "test12".start_with?(regexp2).should be_false
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
