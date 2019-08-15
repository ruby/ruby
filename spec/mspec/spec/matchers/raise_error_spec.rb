require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

class ExpectedException < Exception; end
class UnexpectedException < Exception; end

describe RaiseErrorMatcher do
  it "matches when the proc raises the expected exception" do
    proc = Proc.new { raise ExpectedException }
    matcher = RaiseErrorMatcher.new(ExpectedException, nil)
    matcher.matches?(proc).should == true
  end

  it "executes it's optional block if matched" do
    run = false
    proc = Proc.new { raise ExpectedException }
    matcher = RaiseErrorMatcher.new(ExpectedException, nil) { |error|
      run = true
      error.class.should == ExpectedException
    }

    matcher.matches?(proc).should == true
    run.should == true
  end

  it "matches when the proc raises the expected exception with the expected message" do
    proc = Proc.new { raise ExpectedException, "message" }
    matcher = RaiseErrorMatcher.new(ExpectedException, "message")
    matcher.matches?(proc).should == true
  end

  it "matches when the proc raises the expected exception with a matching message" do
    proc = Proc.new { raise ExpectedException, "some message" }
    matcher = RaiseErrorMatcher.new(ExpectedException, /some/)
    matcher.matches?(proc).should == true
  end

  it "does not match when the proc does not raise the expected exception" do
    exc = UnexpectedException.new
    matcher = RaiseErrorMatcher.new(ExpectedException, nil)

    matcher.matching_exception?(exc).should == false
    lambda {
      matcher.matches?(Proc.new { raise exc })
    }.should raise_error(UnexpectedException)
  end

  it "does not match when the proc raises the expected exception with an unexpected message" do
    exc = ExpectedException.new("unexpected")
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")

    matcher.matching_exception?(exc).should == false
    lambda {
      matcher.matches?(Proc.new { raise exc })
    }.should raise_error(ExpectedException)
  end

  it "does not match when the proc does not raise an exception" do
    proc = Proc.new {}
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc).should == false
  end

  it "provides a useful failure message" do
    exc = UnexpectedException.new("unexpected")
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")

    matcher.matching_exception?(exc).should == false
    lambda {
      matcher.matches?(Proc.new { raise exc })
    }.should raise_error(UnexpectedException)
    matcher.failure_message.should ==
      ["Expected ExpectedException (expected)", "but got UnexpectedException (unexpected)"]
  end

  it "provides a useful failure message when the proc raises the expected exception with an unexpected message" do
    exc = ExpectedException.new("unexpected")
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")

    matcher.matching_exception?(exc).should == false
    lambda {
      matcher.matches?(Proc.new { raise exc })
    }.should raise_error(ExpectedException)
    matcher.failure_message.should ==
      ["Expected ExpectedException (expected)", "but got ExpectedException (unexpected)"]
  end

  it "provides a useful failure message when no exception is raised" do
    proc = Proc.new { 120 }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    matcher.failure_message.should ==
      ["Expected ExpectedException (expected)", "but no exception was raised (120 was returned)"]
  end

  it "provides a useful failure message when no exception is raised and nil is returned" do
    proc = Proc.new { nil }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    matcher.failure_message.should ==
      ["Expected ExpectedException (expected)", "but no exception was raised (nil was returned)"]
  end

  it "provides a useful failure message when no exception is raised and the result raises in #pretty_inspect" do
    result = Object.new
    def result.pretty_inspect
      raise ArgumentError, "bad"
    end
    proc = Proc.new { result }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    matcher.failure_message.should ==
      ["Expected ExpectedException (expected)", "but no exception was raised (#pretty_inspect raised ArgumentError; A #<Object> was returned)"]
  end

  it "provides a useful negative failure message" do
    proc = Proc.new { raise ExpectedException, "expected" }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    matcher.negative_failure_message.should ==
      ["Expected to not get ExpectedException (expected)", ""]
  end

  it "provides a useful negative failure message for strict subclasses of the matched exception class" do
    proc = Proc.new { raise UnexpectedException, "unexpected" }
    matcher = RaiseErrorMatcher.new(Exception, nil)
    matcher.matches?(proc)
    matcher.negative_failure_message.should ==
      ["Expected to not get Exception", "but got UnexpectedException (unexpected)"]
  end
end
