require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe EqualElementMatcher do
  it "matches if it finds an element with the passed name, no matter what attributes/content" do
    expect(EqualElementMatcher.new("A").matches?('<A></A>')).to be_truthy
    expect(EqualElementMatcher.new("A").matches?('<A HREF="http://example.com"></A>')).to be_truthy
    expect(EqualElementMatcher.new("A").matches?('<A HREF="http://example.com"></A>')).to be_truthy

    expect(EqualElementMatcher.new("BASE").matches?('<BASE></A>')).to be_falsey
    expect(EqualElementMatcher.new("BASE").matches?('<A></BASE>')).to be_falsey
    expect(EqualElementMatcher.new("BASE").matches?('<A></A>')).to be_falsey
    expect(EqualElementMatcher.new("BASE").matches?('<A HREF="http://example.com"></A>')).to be_falsey
    expect(EqualElementMatcher.new("BASE").matches?('<A HREF="http://example.com"></A>')).to be_falsey
  end

  it "matches if it finds an element with the passed name and the passed attributes" do
    expect(EqualElementMatcher.new("A", {}).matches?('<A></A>')).to be_truthy
    expect(EqualElementMatcher.new("A", nil).matches?('<A HREF="http://example.com"></A>')).to be_truthy
    expect(EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A HREF="http://example.com"></A>')).to be_truthy

    expect(EqualElementMatcher.new("A", {}).matches?('<A HREF="http://example.com"></A>')).to be_falsey
    expect(EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A></A>')).to be_falsey
    expect(EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A HREF="http://test.com"></A>')).to be_falsey
    expect(EqualElementMatcher.new("A", "HREF" => "http://example.com").matches?('<A HREF="http://example.com" HREF="http://example.com"></A>')).to be_falsey
  end

  it "matches if it finds an element with the passed name, the passed attributes and the passed content" do
    expect(EqualElementMatcher.new("A", {}, "").matches?('<A></A>')).to be_truthy
    expect(EqualElementMatcher.new("A", {"HREF" => "http://example.com"}, "Example").matches?('<A HREF="http://example.com">Example</A>')).to be_truthy

    expect(EqualElementMatcher.new("A", {}, "Test").matches?('<A></A>')).to be_falsey
    expect(EqualElementMatcher.new("A", {"HREF" => "http://example.com"}, "Example").matches?('<A HREF="http://example.com"></A>')).to be_falsey
    expect(EqualElementMatcher.new("A", {"HREF" => "http://example.com"}, "Example").matches?('<A HREF="http://example.com">Test</A>')).to be_falsey
  end

  it "can match unclosed elements" do
    expect(EqualElementMatcher.new("BASE", nil, nil, :not_closed => true).matches?('<BASE>')).to be_truthy
    expect(EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, nil, :not_closed => true).matches?('<BASE HREF="http://example.com">')).to be_truthy
    expect(EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, "Example", :not_closed => true).matches?('<BASE HREF="http://example.com">Example')).to be_truthy

    expect(EqualElementMatcher.new("BASE", {}, nil, :not_closed => true).matches?('<BASE HREF="http://example.com">')).to be_falsey
    expect(EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, "", :not_closed => true).matches?('<BASE HREF="http://example.com">Example')).to be_falsey
    expect(EqualElementMatcher.new("BASE", {"HREF" => "http://example.com"}, "Test", :not_closed => true).matches?('<BASE HREF="http://example.com">Example')).to be_falsey
  end

  it "provides a useful failure message" do
    equal_element = EqualElementMatcher.new("A", {}, "Test")
    expect(equal_element.matches?('<A></A>')).to be_falsey
    expect(equal_element.failure_message).to eq([%{Expected "<A></A>"}, %{to be a 'A' element with no attributes and "Test" as content}])

    equal_element = EqualElementMatcher.new("A", {}, "")
    expect(equal_element.matches?('<A>Test</A>')).to be_falsey
    expect(equal_element.failure_message).to eq([%{Expected "<A>Test</A>"}, %{to be a 'A' element with no attributes and no content}])

    equal_element = EqualElementMatcher.new("A", "HREF" => "http://www.example.com")
    expect(equal_element.matches?('<A>Test</A>')).to be_falsey
    expect(equal_element.failure_message).to eq([%{Expected "<A>Test</A>"}, %{to be a 'A' element with HREF="http://www.example.com" and any content}])
  end

  it "provides a useful negative failure message" do
    equal_element = EqualElementMatcher.new("A", {}, "Test")
    expect(equal_element.matches?('<A></A>')).to be_falsey
    expect(equal_element.negative_failure_message).to eq([%{Expected "<A></A>"}, %{not to be a 'A' element with no attributes and "Test" as content}])

    equal_element = EqualElementMatcher.new("A", {}, "")
    expect(equal_element.matches?('<A>Test</A>')).to be_falsey
    expect(equal_element.negative_failure_message).to eq([%{Expected "<A>Test</A>"}, %{not to be a 'A' element with no attributes and no content}])

    equal_element = EqualElementMatcher.new("A", "HREF" => "http://www.example.com")
    expect(equal_element.matches?('<A>Test</A>')).to be_falsey
    expect(equal_element.negative_failure_message).to eq([%{Expected "<A>Test</A>"}, %{not to be a 'A' element with HREF="http://www.example.com" and any content}])
  end
end
