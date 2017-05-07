require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/matchers'

describe OutputToFDMatcher do
  # Figure out how in the hell to achieve this
  it "matches when running the block produces the expected output to the given FD" do
    output_to_fd("Hi\n", STDERR).matches?(lambda { $stderr.print "Hi\n" }).should == true
  end

  it "does not match if running the block does not produce the expected output to the FD" do
    output_to_fd("Hi\n", STDERR).matches?(lambda { $stderr.puts("Hello\n") }).should == false
  end

  it "propagate the exception if one is thrown while matching" do
    exc = RuntimeError.new("propagates")
    lambda {
      output_to_fd("Hi\n", STDERR).matches?(lambda {
        raise exc
      }).should == false
    }.should raise_error(exc)
  end

  it "defaults to matching against STDOUT" do
    output_to_fd("Hi\n").matches?(lambda { $stdout.print "Hi\n" }).should == true
  end

  it "accepts any IO instance" do
    io = IO.new STDOUT.fileno
    output_to_fd("Hi\n", io).matches?(lambda { io.print "Hi\n" }).should == true
  end

  it "allows matching with a Regexp" do
    s = "Hi there\n"
    output_to_fd(/Hi/, STDERR).matches?(lambda { $stderr.print s }).should == true
    output_to_fd(/Hi?/, STDERR).matches?(lambda { $stderr.print s }).should == true
    output_to_fd(/[hH]i?/, STDERR).matches?(lambda { $stderr.print s }).should == true
    output_to_fd(/.*/, STDERR).matches?(lambda { $stderr.print s }).should == true
    output_to_fd(/H.*?here/, STDERR).matches?(lambda { $stderr.print s }).should == true
    output_to_fd(/Ahoy/, STDERR).matches?(lambda { $stderr.print s }).should == false
  end
end
