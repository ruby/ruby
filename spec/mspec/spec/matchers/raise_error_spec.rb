require 'spec_helper'

class ExpectedException < Exception; end
class UnexpectedException < Exception; end

RSpec.describe RaiseErrorMatcher do
  before :each do
    state = double("run state").as_null_object
    allow(MSpec).to receive(:current).and_return(state)
  end

  it "matches when the proc raises the expected exception" do
    proc = Proc.new { raise ExpectedException }
    matcher = RaiseErrorMatcher.new(ExpectedException, nil)
    expect(matcher.matches?(proc)).to eq(true)
  end

  it "executes its optional {/} block if matched" do
    ensure_mspec_method(-> {}.method(:should))

    run = false
    -> { raise ExpectedException }.should PublicMSpecMatchers.raise_error { |error|
      expect(error.class).to eq(ExpectedException)
      run = true
    }
    expect(run).to eq(true)
  end

  it "executes its optional do/end block if matched" do
    ensure_mspec_method(-> {}.method(:should))

    run = false
    -> { raise ExpectedException }.should PublicMSpecMatchers.raise_error do |error|
      expect(error.class).to eq(ExpectedException)
      run = true
    end
    expect(run).to eq(true)
  end

  it "matches when the proc raises the expected exception with the expected message" do
    proc = Proc.new { raise ExpectedException, "message" }
    matcher = RaiseErrorMatcher.new(ExpectedException, "message")
    expect(matcher.matches?(proc)).to eq(true)
  end

  it "matches when the proc raises the expected exception with a matching message" do
    proc = Proc.new { raise ExpectedException, "some message" }
    matcher = RaiseErrorMatcher.new(ExpectedException, /some/)
    expect(matcher.matches?(proc)).to eq(true)
  end

  it "does not match when the proc does not raise the expected exception" do
    exc = UnexpectedException.new
    matcher = RaiseErrorMatcher.new(ExpectedException, nil)

    expect(matcher.matching_exception?(exc)).to eq(false)
    expect {
      matcher.matches?(Proc.new { raise exc })
    }.to raise_error(UnexpectedException)
  end

  it "does not match when the proc raises the expected exception with an unexpected message" do
    exc = ExpectedException.new("unexpected")
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")

    expect(matcher.matching_exception?(exc)).to eq(false)
    expect {
      matcher.matches?(Proc.new { raise exc })
    }.to raise_error(ExpectedException)
  end

  it "does not match when the proc does not raise an exception" do
    proc = Proc.new {}
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    expect(matcher.matches?(proc)).to eq(false)
  end

  it "provides a useful failure message when the exception class differs" do
    exc = UnexpectedException.new("message")
    matcher = RaiseErrorMatcher.new(ExpectedException, "message")

    expect(matcher.matching_exception?(exc)).to eq(false)
    begin
      matcher.matches?(Proc.new { raise exc })
    rescue UnexpectedException => e
      expect(matcher.failure_message).to eq(
        ["Expected ExpectedException (message)", "but got: UnexpectedException (message)"]
      )
      expect(ExceptionState.new(nil, nil, e).message).to eq(
        "Expected ExpectedException (message)\nbut got: UnexpectedException (message)"
      )
    else
      raise "no exception"
    end
  end

  it "provides a useful failure message when the proc raises the expected exception with an unexpected message" do
    exc = ExpectedException.new("unexpected")
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")

    expect(matcher.matching_exception?(exc)).to eq(false)
    begin
      matcher.matches?(Proc.new { raise exc })
    rescue ExpectedException => e
      expect(matcher.failure_message).to eq(
        ["Expected ExpectedException (expected)", "but got: ExpectedException (unexpected)"]
      )
      expect(ExceptionState.new(nil, nil, e).message).to eq(
        "Expected ExpectedException (expected)\nbut got: ExpectedException (unexpected)"
      )
    else
      raise "no exception"
    end
  end

  it "provides a useful failure message when both the exception class and message differ" do
    exc = UnexpectedException.new("unexpected")
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")

    expect(matcher.matching_exception?(exc)).to eq(false)
    begin
      matcher.matches?(Proc.new { raise exc })
    rescue UnexpectedException => e
      expect(matcher.failure_message).to eq(
          ["Expected ExpectedException (expected)", "but got: UnexpectedException (unexpected)"]
      )
      expect(ExceptionState.new(nil, nil, e).message).to eq(
          "Expected ExpectedException (expected)\nbut got: UnexpectedException (unexpected)"
      )
    else
      raise "no exception"
    end
  end

  it "provides a useful failure message when no exception is raised" do
    proc = Proc.new { 120 }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected ExpectedException (expected)", "but no exception was raised (120 was returned)"]
    )
  end

  it "provides a useful failure message when no exception is raised and nil is returned" do
    proc = Proc.new { nil }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected ExpectedException (expected)", "but no exception was raised (nil was returned)"]
    )
  end

  it "provides a useful failure message when no exception is raised and the result raises in #pretty_inspect" do
    result = Object.new
    def result.pretty_inspect
      raise ArgumentError, "bad"
    end
    proc = Proc.new { result }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected ExpectedException (expected)", "but no exception was raised (#<Object>(#pretty_inspect raised #<ArgumentError: bad>) was returned)"]
    )
  end

  it "provides a useful negative failure message" do
    proc = Proc.new { raise ExpectedException, "expected" }
    matcher = RaiseErrorMatcher.new(ExpectedException, "expected")
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected to not get ExpectedException (expected)", ""]
    )
  end

  it "provides a useful negative failure message for strict subclasses of the matched exception class" do
    proc = Proc.new { raise UnexpectedException, "unexpected" }
    matcher = RaiseErrorMatcher.new(Exception, nil)
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected to not get Exception", "but got: UnexpectedException (unexpected)"]
    )
  end
end
