require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe OutputMatcher do
  it "matches when executing the proc results in the expected output to $stdout" do
    proc = Proc.new { puts "bang!" }
    expect(OutputMatcher.new("bang!\n", nil).matches?(proc)).to eq(true)
    expect(OutputMatcher.new("pop", nil).matches?(proc)).to eq(false)
    expect(OutputMatcher.new(/bang/, nil).matches?(proc)).to eq(true)
    expect(OutputMatcher.new(/po/, nil).matches?(proc)).to eq(false)
  end

  it "matches when executing the proc results in the expected output to $stderr" do
    proc = Proc.new { $stderr.write "boom!" }
    expect(OutputMatcher.new(nil, "boom!").matches?(proc)).to eq(true)
    expect(OutputMatcher.new(nil, "fizzle").matches?(proc)).to eq(false)
    expect(OutputMatcher.new(nil, /boom/).matches?(proc)).to eq(true)
    expect(OutputMatcher.new(nil, /fizzl/).matches?(proc)).to eq(false)
  end

  it "provides a useful failure message" do
    proc = Proc.new { print "unexpected"; $stderr.print "unerror" }
    matcher = OutputMatcher.new("expected", "error")
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected:\n  $stdout: \"expected\"\n  $stderr: \"error\"\n",
       "     got:\n  $stdout: \"unexpected\"\n  $stderr: \"unerror\"\n"]
    )
    matcher = OutputMatcher.new("expected", nil)
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected:\n  $stdout: \"expected\"\n",
       "     got:\n  $stdout: \"unexpected\"\n"]
    )
    matcher = OutputMatcher.new(nil, "error")
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected:\n  $stderr: \"error\"\n",
       "     got:\n  $stderr: \"unerror\"\n"]
    )
    matcher = OutputMatcher.new(/base/, nil)
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected:\n  $stdout: /base/\n",
       "     got:\n  $stdout: \"unexpected\"\n"]
    )
    matcher = OutputMatcher.new(nil, /octave/)
    matcher.matches?(proc)
    expect(matcher.failure_message).to eq(
      ["Expected:\n  $stderr: /octave/\n",
       "     got:\n  $stderr: \"unerror\"\n"]
    )
  end

  it "provides a useful negative failure message" do
    proc = Proc.new { puts "expected"; $stderr.puts "error" }
    matcher = OutputMatcher.new("expected", "error")
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected output not to be:\n", "  $stdout: \"expected\"\n  $stderr: \"error\"\n"]
    )
    matcher = OutputMatcher.new("expected", nil)
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected output not to be:\n", "  $stdout: \"expected\"\n"]
    )
    matcher = OutputMatcher.new(nil, "error")
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected output not to be:\n", "  $stderr: \"error\"\n"]
    )
    matcher = OutputMatcher.new(/expect/, nil)
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected output not to be:\n", "  $stdout: \"expected\"\n"]
    )
    matcher = OutputMatcher.new(nil, /err/)
    matcher.matches?(proc)
    expect(matcher.negative_failure_message).to eq(
      ["Expected output not to be:\n", "  $stderr: \"error\"\n"]
    )
  end
end
