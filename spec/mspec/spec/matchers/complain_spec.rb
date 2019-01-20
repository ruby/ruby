require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe ComplainMatcher do
  it "matches when executing the proc results in output to $stderr" do
    proc = lambda { warn "I'm gonna tell yo mama" }
    ComplainMatcher.new(nil).matches?(proc).should == true
  end

  it "maches when executing the proc results in the expected output to $stderr" do
    proc = lambda { warn "Que haces?" }
    ComplainMatcher.new("Que haces?\n").matches?(proc).should == true
    ComplainMatcher.new("Que pasa?\n").matches?(proc).should == false
    ComplainMatcher.new(/Que/).matches?(proc).should == true
    ComplainMatcher.new(/Quoi/).matches?(proc).should == false
  end

  it "does not match when there is no output to $stderr" do
    ComplainMatcher.new(nil).matches?(lambda {}).should == false
  end

  it "provides a useful failure message" do
    matcher = ComplainMatcher.new(nil)
    matcher.matches?(lambda { })
    matcher.failure_message.should == ["Expected a warning", "but received none"]
    matcher = ComplainMatcher.new("listen here")
    matcher.matches?(lambda { warn "look out" })
    matcher.failure_message.should ==
      ["Expected warning: \"listen here\"", "but got: \"look out\""]
    matcher = ComplainMatcher.new(/talk/)
    matcher.matches?(lambda { warn "listen up" })
    matcher.failure_message.should ==
      ["Expected warning to match: /talk/", "but got: \"listen up\""]
  end

  it "provides a useful negative failure message" do
    proc = lambda { warn "ouch" }
    matcher = ComplainMatcher.new(nil)
    matcher.matches?(proc)
    matcher.negative_failure_message.should ==
      ["Unexpected warning: ", "\"ouch\""]
    matcher = ComplainMatcher.new("ouchy")
    matcher.matches?(proc)
    matcher.negative_failure_message.should ==
      ["Expected warning: \"ouchy\"", "but got: \"ouch\""]
    matcher = ComplainMatcher.new(/ou/)
    matcher.matches?(proc)
    matcher.negative_failure_message.should ==
      ["Expected warning not to match: /ou/", "but got: \"ouch\""]
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
      verbose.should == true

      ComplainMatcher.new(nil, verbose: false).matches?(proc)
      verbose.should == false
    end

    it "sets $VERBOSE with false by default" do
      verbose = nil
      proc = lambda { verbose = $VERBOSE }

      ComplainMatcher.new(nil).matches?(proc)
      verbose.should == false
    end

    it "does not have side effect" do
      proc = lambda { safe_value = $VERBOSE }

      lambda do
        ComplainMatcher.new(nil, verbose: true).matches?(proc)
      end.should_not change { $VERBOSE }
    end

    it "accepts a verbose level as single argument" do
      verbose = nil
      proc = lambda { verbose = $VERBOSE }

      ComplainMatcher.new(verbose: true).matches?(proc)
      verbose.should == true
    end
  end
end
