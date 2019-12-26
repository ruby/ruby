require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'
require 'time'

describe SpecPositiveOperatorMatcher, "== operator" do
  it "provides a failure message that 'Expected x to equal y'" do
    lambda {
      SpecPositiveOperatorMatcher.new(1) == 2
    }.should raise_error(SpecExpectationNotMetError, "Expected 1 == 2\nto be truthy but was false")
  end

  it "does not raise an exception when == returns true" do
    SpecPositiveOperatorMatcher.new(1) == 1
  end
end

describe SpecPositiveOperatorMatcher, "=~ operator" do
  it "provides a failure message that 'Expected \"x\" to match y'" do
    lambda {
      SpecPositiveOperatorMatcher.new('real') =~ /fake/
    }.should raise_error(SpecExpectationNotMetError, "Expected \"real\" =~ /fake/\nto be truthy but was nil")
  end

  it "does not raise an exception when =~ returns true" do
    SpecPositiveOperatorMatcher.new('real') =~ /real/
  end
end

describe SpecPositiveOperatorMatcher, "> operator" do
  it "provides a failure message that 'Expected x to be greater than y'" do
    lambda {
      SpecPositiveOperatorMatcher.new(4) > 5
    }.should raise_error(SpecExpectationNotMetError, "Expected 4 > 5\nto be truthy but was false")
  end

  it "does not raise an exception when > returns true" do
    SpecPositiveOperatorMatcher.new(5) > 4
  end
end

describe SpecPositiveOperatorMatcher, ">= operator" do
  it "provides a failure message that 'Expected x to be greater than or equal to y'" do
    lambda {
      SpecPositiveOperatorMatcher.new(4) >= 5
    }.should raise_error(SpecExpectationNotMetError, "Expected 4 >= 5\nto be truthy but was false")
  end

  it "does not raise an exception when > returns true" do
    SpecPositiveOperatorMatcher.new(5) >= 4
    SpecPositiveOperatorMatcher.new(5) >= 5
  end
end

describe SpecPositiveOperatorMatcher, "< operator" do
  it "provides a failure message that 'Expected x to be less than y'" do
    lambda {
      SpecPositiveOperatorMatcher.new(5) < 4
    }.should raise_error(SpecExpectationNotMetError, "Expected 5 < 4\nto be truthy but was false")
  end

  it "does not raise an exception when < returns true" do
    SpecPositiveOperatorMatcher.new(4) < 5
  end
end

describe SpecPositiveOperatorMatcher, "<= operator" do
  it "provides a failure message that 'Expected x to be less than or equal to y'" do
    lambda {
      SpecPositiveOperatorMatcher.new(5) <= 4
    }.should raise_error(SpecExpectationNotMetError, "Expected 5 <= 4\nto be truthy but was false")
  end

  it "does not raise an exception when < returns true" do
    SpecPositiveOperatorMatcher.new(4) <= 5
    SpecPositiveOperatorMatcher.new(4) <= 4
  end
end

describe SpecPositiveOperatorMatcher, "arbitrary predicates" do
  it "do not raise an exception when the predicate is truthy" do
    SpecPositiveOperatorMatcher.new(2).eql?(2)
    SpecPositiveOperatorMatcher.new(2).equal?(2)
    SpecPositiveOperatorMatcher.new([1, 2, 3]).include?(2)
    SpecPositiveOperatorMatcher.new("abc").start_with?("ab")
    SpecPositiveOperatorMatcher.new("abc").start_with?("d", "a")
    SpecPositiveOperatorMatcher.new(3).odd?
    SpecPositiveOperatorMatcher.new([1, 2]).any? { |e| e.even? }
  end

  it "provide a failure message when the predicate returns a falsy value" do
    lambda {
      SpecPositiveOperatorMatcher.new(2).eql?(3)
    }.should raise_error(SpecExpectationNotMetError, "Expected 2.eql? 3\nto be truthy but was false")
    lambda {
      SpecPositiveOperatorMatcher.new(2).equal?(3)
    }.should raise_error(SpecExpectationNotMetError, "Expected 2.equal? 3\nto be truthy but was false")
    lambda {
      SpecPositiveOperatorMatcher.new([1, 2, 3]).include?(4)
    }.should raise_error(SpecExpectationNotMetError, "Expected [1, 2, 3].include? 4\nto be truthy but was false")
    lambda {
      SpecPositiveOperatorMatcher.new("abc").start_with?("de")
    }.should raise_error(SpecExpectationNotMetError, "Expected \"abc\".start_with? \"de\"\nto be truthy but was false")
    lambda {
      SpecPositiveOperatorMatcher.new("abc").start_with?("d", "e")
    }.should raise_error(SpecExpectationNotMetError, "Expected \"abc\".start_with? \"d\", \"e\"\nto be truthy but was false")
    lambda {
      SpecPositiveOperatorMatcher.new(2).odd?
    }.should raise_error(SpecExpectationNotMetError, "Expected 2.odd?\nto be truthy but was false")
    lambda {
      SpecPositiveOperatorMatcher.new([1, 3]).any? { |e| e.even? }
    }.should raise_error(SpecExpectationNotMetError, "Expected [1, 3].any? { ... }\nto be truthy but was false")
  end
end

describe SpecNegativeOperatorMatcher, "arbitrary predicates" do
  it "do not raise an exception when the predicate returns a falsy value" do
    SpecNegativeOperatorMatcher.new(2).eql?(3)
    SpecNegativeOperatorMatcher.new(2).equal?(3)
    SpecNegativeOperatorMatcher.new([1, 2, 3]).include?(4)
    SpecNegativeOperatorMatcher.new("abc").start_with?("de")
    SpecNegativeOperatorMatcher.new("abc").start_with?("d", "e")
    SpecNegativeOperatorMatcher.new(2).odd?
    SpecNegativeOperatorMatcher.new([1, 3]).any? { |e| e.even? }
  end

  it "provide a failure message when the predicate returns a truthy value" do
    lambda {
      SpecNegativeOperatorMatcher.new(2).eql?(2)
    }.should raise_error(SpecExpectationNotMetError, "Expected 2.eql? 2\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new(2).equal?(2)
    }.should raise_error(SpecExpectationNotMetError, "Expected 2.equal? 2\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new([1, 2, 3]).include?(2)
    }.should raise_error(SpecExpectationNotMetError, "Expected [1, 2, 3].include? 2\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new("abc").start_with?("ab")
    }.should raise_error(SpecExpectationNotMetError, "Expected \"abc\".start_with? \"ab\"\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new("abc").start_with?("d", "a")
    }.should raise_error(SpecExpectationNotMetError, "Expected \"abc\".start_with? \"d\", \"a\"\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new(3).odd?
    }.should raise_error(SpecExpectationNotMetError, "Expected 3.odd?\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new([1, 2]).any? { |e| e.even? }
    }.should raise_error(SpecExpectationNotMetError, "Expected [1, 2].any? { ... }\nto be falsy but was true")
  end
end

describe SpecNegativeOperatorMatcher, "== operator" do
  it "provides a failure message that 'Expected x not to equal y'" do
    lambda {
      SpecNegativeOperatorMatcher.new(1) == 1
    }.should raise_error(SpecExpectationNotMetError, "Expected 1 == 1\nto be falsy but was true")
  end

  it "does not raise an exception when == returns false" do
    SpecNegativeOperatorMatcher.new(1) == 2
  end
end

describe SpecNegativeOperatorMatcher, "=~ operator" do
  it "provides a failure message that 'Expected \"x\" not to match /y/'" do
    lambda {
      SpecNegativeOperatorMatcher.new('real') =~ /real/
    }.should raise_error(SpecExpectationNotMetError, "Expected \"real\" =~ /real/\nto be falsy but was 0")
  end

  it "does not raise an exception when =~ returns false" do
    SpecNegativeOperatorMatcher.new('real') =~ /fake/
  end
end

describe SpecNegativeOperatorMatcher, "< operator" do
  it "provides a failure message that 'Expected x not to be less than y'" do
    lambda {
      SpecNegativeOperatorMatcher.new(4) < 5
    }.should raise_error(SpecExpectationNotMetError, "Expected 4 < 5\nto be falsy but was true")
  end

  it "does not raise an exception when < returns false" do
    SpecNegativeOperatorMatcher.new(5) < 4
  end
end

describe SpecNegativeOperatorMatcher, "<= operator" do
  it "provides a failure message that 'Expected x not to be less than or equal to y'" do
    lambda {
      SpecNegativeOperatorMatcher.new(4) <= 5
    }.should raise_error(SpecExpectationNotMetError, "Expected 4 <= 5\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new(5) <= 5
    }.should raise_error(SpecExpectationNotMetError, "Expected 5 <= 5\nto be falsy but was true")
  end

  it "does not raise an exception when <= returns false" do
    SpecNegativeOperatorMatcher.new(5) <= 4
  end
end

describe SpecNegativeOperatorMatcher, "> operator" do
  it "provides a failure message that 'Expected x not to be greater than y'" do
    lambda {
      SpecNegativeOperatorMatcher.new(5) > 4
    }.should raise_error(SpecExpectationNotMetError, "Expected 5 > 4\nto be falsy but was true")
  end

  it "does not raise an exception when > returns false" do
    SpecNegativeOperatorMatcher.new(4) > 5
  end
end

describe SpecNegativeOperatorMatcher, ">= operator" do
  it "provides a failure message that 'Expected x not to be greater than or equal to y'" do
    lambda {
      SpecNegativeOperatorMatcher.new(5) >= 4
    }.should raise_error(SpecExpectationNotMetError, "Expected 5 >= 4\nto be falsy but was true")
    lambda {
      SpecNegativeOperatorMatcher.new(5) >= 5
    }.should raise_error(SpecExpectationNotMetError, "Expected 5 >= 5\nto be falsy but was true")
  end

  it "does not raise an exception when >= returns false" do
    SpecNegativeOperatorMatcher.new(4) >= 5
  end
end
