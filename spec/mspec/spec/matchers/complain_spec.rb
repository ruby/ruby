require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe ComplainMatcher do
  it "matches when executing the proc results in output to $stderr" do
    proc = lambda { warn "I'm gonna tell yo mama" }
    expect(ComplainMatcher.new(nil).matches?(proc)).to eq(true)
  end

  it "matches when executing the proc results in the expected output to $stderr" do
    proc = lambda { warn "Que haces?" }
    expect(ComplainMatcher.new("Que haces?\n").matches?(proc)).to eq(true)
    expect(ComplainMatcher.new("Que pasa?\n").matches?(proc)).to eq(false)
    expect(ComplainMatcher.new(/Que/).matches?(proc)).to eq(true)
    expect(ComplainMatcher.new(/Quoi/).matches?(proc)).to eq(false)
  end

  it "does not match when there is no output to $stderr" do
    expect(ComplainMatcher.new(nil).matches?(lambda {})).to eq(false)
  end

  it "provides a useful failure message" do
    matcher = ComplainMatcher.new(nil)
    matcher.matches?(lambda { })
    expect(matcher.failure_message).to eq(["Expected a warning", "but received none"])
    matcher = ComplainMatcher.new("listen here")
    matcher.matches?(lambda { warn "look out" })
    expect(matcher.failure_message).to eq(
      ["Expected warning: \"listen here\"", "but got: \"look out\""]
    )
    matcher = ComplainMatcher.new(/talk/)
    matcher.matches?(lambda { warn "listen up" })
    expect(matcher.failure_message).to eq(
      ["Expected warning to match: /talk/", "but got: \"listen up\""]
    )
  end

  it "provides a useful negative failure message" do
    proc = lambda { warn "ouch" }
    matcher = ComplainMatcher.new(nil)
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Unexpected warning: ", "\"ouch\""]
    )
    matcher = ComplainMatcher.new("ouchy")
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected warning: \"ouchy\"", "but got: \"ouch\""]
    )
    matcher = ComplainMatcher.new(/ou/)
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected warning not to match: /ou/", "but got: \"ouch\""]
    )
  end

  context "`verbose` option specified" do
    before do
      $VERBOSE, @verbose = nil, $VERBOSE
    end

    after do
      $VERBOSE = @verbose
    end

    it "sets $VERBOSE with specified second optional parameter" do
      verbose = nil
      proc = lambda { verbose = $VERBOSE }

      ComplainMatcher.new(nil, verbose: true).matches?(proc)
      expect(verbose).to eq(true)

      ComplainMatcher.new(nil, verbose: false).matches?(proc)
      expect(verbose).to eq(false)
    end

    it "sets $VERBOSE with false by default" do
      verbose = nil
      proc = lambda { verbose = $VERBOSE }

      ComplainMatcher.new(nil).matches?(proc)
      expect(verbose).to eq(false)
    end

    it "does not have side effect" do
      proc = lambda { safe_value = $VERBOSE }

      expect do
        ComplainMatcher.new(nil, verbose: true).matches?(proc)
      end.not_to change { $VERBOSE }
    end

    it "accepts a verbose level as single argument" do
      verbose = nil
      proc = lambda { verbose = $VERBOSE }

      ComplainMatcher.new(verbose: true).matches?(proc)
      expect(verbose).to eq(true)
    end
  end
end
