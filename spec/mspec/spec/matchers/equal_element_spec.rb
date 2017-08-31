require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe EqualElementMatcher do
  it "matches if it finds an element with the passed name, no matter what attributes/content" do
    EqualElementMatcher.new("A").matches?('<A></A>').should be_true
    EqualElementMatcher.new("A").matches?('<A HREF="http://example.com"></A>').should be_true
    EqualElementMatcher.new("A").matches?('<A HREF="http://example.com"></A>').should be_true

    EqualElementMatcher.new("BASE").matches?('<BASE></A>').should be_false
    EqualElementMatcher.new("BASE").matches?('<A></BASE>').should be_false
    EqualElementMatcher.new("BASE").matches?('<A></A>').should be_false
    EqualElementMatcher.new("BASE").matches?('<A HREF="http://example.com"></A>').should be_false
    EqualElementMatcher.new("BASE").matches?('<A HREF="http://example.com"></A>').should be_false
  end

  it "matches if it finds an element with the passed name and the passed attributes" do
    EqualElementMatcher.new("A", {}).matches?('<A></A>').should be_true
    EqualElementMatcher.new("A", nil).matches?('<A HREF="http://example.com"></A>').should be_true
    EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A HREF="http://example.com"></A>').should be_true

    EqualElementMatcher.new("A", {}).matches?('<A HREF="http://example.com"></A>').should be_false
    EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A></A>').should be_false
    EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A HREF="http://test.com"></A>').should be_false
    EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A HREF="http://example.com" HREF="http://example.com"></A>').should be_false
  end

  it "matches if it finds an element with the passed name, the passed attributes and the passed content" do
    EqualElementMatcher.new("A", {}, "").matches?('<A></A>').should be_true
    EqualElementMatcher.new("A", {"HREF" => "http://example.com"}, "Example").matches?('<A HREF="http://example.com">Example</A>').should be_true

    EqualElementMatcher.new("A", {}, "Test").matches?('<A></A>').should be_false
    EqualElementMatcher.new("A", {"HREF" => "http://example.com"}, "Example").matches?('<A HREF="http://example.com"></A>').should be_false
    EqualElementMatcher.new("A", {"HREF" => "http://example.com"}, "Example").matches?('<A HREF="http://example.com">Test</A>').should be_false
  end

  it "can match unclosed elements" do
    EqualElementMatcher.new("BASE", nil, nil, :not_closed => true).matches?('<BASE>').should be_true
    EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, nil, :not_closed => true).matches?('<BASE HREF="http://example.com">').should be_true
    EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, "Example", :not_closed => true).matches?('<BASE HREF="http://example.com">Example').should be_true

    EqualElementMatcher.new("BASE", {}, nil, :not_closed => true).matches?('<BASE HREF="http://example.com">').should be_false
    EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, "", :not_closed => true).matches?('<BASE HREF="http://example.com">Example').should be_false
    EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, "Test", :not_closed => true).matches?('<BASE HREF="http://example.com">Example').should be_false
  end

  it "provides a useful failure message" do
    equal_element = EqualElementMatcher.new("A", {}, "Test")
    equal_element.matches?('<A></A>').should be_false
    equal_element.failure_message.should == [%{Expected "<A></A>"\n}, %{to be a 'A' element with no attributes and "Test" as content}]

    equal_element = EqualElementMatcher.new("A", {}, "")
    equal_element.matches?('<A>Test</A>').should be_false
    equal_element.failure_message.should == [%{Expected "<A>Test</A>"\n}, %{to be a 'A' element with no attributes and no content}]

    equal_element = EqualElementMatcher.new("A", "HREF" => "http://www.example.com")
    equal_element.matches?('<A>Test</A>').should be_false
    equal_element.failure_message.should == [%{Expected "<A>Test</A>"\n}, %{to be a 'A' element with HREF="http://www.example.com" and any content}]
  end

  it "provides a useful negative failure message" do
    equal_element = EqualElementMatcher.new("A", {}, "Test")
    equal_element.matches?('<A></A>').should be_false
    equal_element.negative_failure_message.should == [%{Expected "<A></A>"\n}, %{not to be a 'A' element with no attributes and "Test" as content}]

    equal_element = EqualElementMatcher.new("A", {}, "")
    equal_element.matches?('<A>Test</A>').should be_false
    equal_element.negative_failure_message.should == [%{Expected "<A>Test</A>"\n}, %{not to be a 'A' element with no attributes and no content}]

    equal_element = EqualElementMatcher.new("A", "HREF" => "http://www.example.com")
    equal_element.matches?('<A>Test</A>').should be_false
    equal_element.negative_failure_message.should == [%{Expected "<A>Test</A>"\n}, %{not to be a 'A' element with HREF="http://www.example.com" and any content}]
  end
end
