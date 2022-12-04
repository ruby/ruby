require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

RSpec.describe OutputToFDMatcher do
  # Figure out how in the hell to achieve this
  it "matches when running the block produces the expected output to the given FD" do
    expect(OutputToFDMatcher.new("Hi\n", STDERR).matches?(lambda { $stderr.print "Hi\n" })).to eq(true)
  end

  it "does not match if running the block does not produce the expected output to the FD" do
    expect(OutputToFDMatcher.new("Hi\n", STDERR).matches?(lambda { $stderr.puts("Hello\n") })).to eq(false)
  end

  it "propagate the exception if one is thrown while matching" do
    exc = RuntimeError.new("propagates")
    expect {
      expect(OutputToFDMatcher.new("Hi\n", STDERR).matches?(lambda {
        raise exc
      })).to eq(false)
    }.to raise_error(exc)
  end

  it "defaults to matching against STDOUT" do
    object = Object.new
    object.extend MSpecMatchers
    expect(object.send(:output_to_fd, "Hi\n").matches?(lambda { $stdout.print "Hi\n" })).to eq(true)
  end

  it "accepts any IO instance" do
    io = IO.new STDOUT.fileno
    expect(OutputToFDMatcher.new("Hi\n", io).matches?(lambda { io.print "Hi\n" })).to eq(true)
  end

  it "allows matching with a Regexp" do
    s = "Hi there\n"
    expect(OutputToFDMatcher.new(/Hi/, STDERR).matches?(lambda { $stderr.print s })).to eq(true)
    expect(OutputToFDMatcher.new(/Hi?/, STDERR).matches?(lambda { $stderr.print s })).to eq(true)
    expect(OutputToFDMatcher.new(/[hH]i?/, STDERR).matches?(lambda { $stderr.print s })).to eq(true)
    expect(OutputToFDMatcher.new(/.*/, STDERR).matches?(lambda { $stderr.print s })).to eq(true)
    expect(OutputToFDMatcher.new(/H.*?here/, STDERR).matches?(lambda { $stderr.print s })).to eq(true)
    expect(OutputToFDMatcher.new(/Ahoy/, STDERR).matches?(lambda { $stderr.print s })).to eq(false)
  end
end
