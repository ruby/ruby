# -*- coding: utf-8 -*-
require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/junit'
require 'mspec/runner/example'

describe JUnitFormatter, "#initialize" do
  it "permits zero arguments" do
    lambda { JUnitFormatter.new }.should_not raise_error
  end

  it "accepts one argument" do
    lambda { JUnitFormatter.new nil }.should_not raise_error
  end
end

describe JUnitFormatter, "#print" do
  before :each do
    $stdout = IOStub.new
    @out = IOStub.new
    File.stub(:open).and_return(@out)
    @formatter = JUnitFormatter.new "some/file"
  end

  after :each do
    $stdout = STDOUT
  end

  it "writes to $stdout if #switch has not been called" do
    @formatter.print "begonias"
    $stdout.should == "begonias"
    @out.should == ""
  end

  it "writes to the file passed to #initialize once #switch has been called" do
    @formatter.switch
    @formatter.print "begonias"
    $stdout.should == ""
    @out.should == "begonias"
  end

  it "writes to $stdout once #switch is called if no file was passed to #initialize" do
    formatter = JUnitFormatter.new
    formatter.switch
    formatter.print "begonias"
    $stdout.should == "begonias"
    @out.should == ""
  end
end

describe JUnitFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    @counter = double("counter").as_null_object
    @tally.stub(:counter).and_return(@counter)
    TallyAction.stub(:new).and_return(@tally)

    @timer = double("timer").as_null_object
    TimerAction.stub(:new).and_return(@timer)

    $stdout = IOStub.new
    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")

    @formatter = JUnitFormatter.new
    @formatter.stub(:backtrace).and_return("")
    MSpec.stub(:register)
    @formatter.register

    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
  end

  after :each do
    $stdout = STDOUT
  end

  it "calls #switch" do
    @formatter.should_receive(:switch)
    @formatter.finish
  end

  it "outputs a failure message and backtrace" do
    @formatter.finish
    $stdout.should include 'message="error in describe it" type="error"'
    $stdout.should include "MSpecExampleError: broken\n"
    $stdout.should include "path/to/some/file.rb:35:in method"
  end

  it "encodes message and backtrace in latin1 for jenkins" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken…")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in methød")
    @formatter.exception exc
    @formatter.finish
    $stdout.should =~ /MSpecExampleError: broken((\.\.\.)|\?)\n/
    $stdout.should =~ /path\/to\/some\/file\.rb:35:in meth(\?|o)d/
  end

  it "outputs an elapsed time" do
    @timer.should_receive(:elapsed).and_return(4.2)
    @formatter.finish
    $stdout.should include 'time="4.2"'
  end

  it "outputs overall elapsed time" do
    @timer.should_receive(:elapsed).and_return(4.2)
    @formatter.finish
    $stdout.should include 'timeCount="4.2"'
  end

  it "outputs the number of examples as test count" do
    @counter.should_receive(:examples).and_return(9)
    @formatter.finish
    $stdout.should include 'tests="9"'
  end

  it "outputs overall number of examples as test count" do
    @counter.should_receive(:examples).and_return(9)
    @formatter.finish
    $stdout.should include 'testCount="9"'
  end

  it "outputs a failure count" do
    @counter.should_receive(:failures).and_return(2)
    @formatter.finish
    $stdout.should include 'failureCount="2"'
  end

  it "outputs overall failure count" do
    @counter.should_receive(:failures).and_return(2)
    @formatter.finish
    $stdout.should include 'failures="2"'
  end

  it "outputs an error count" do
    @counter.should_receive(:errors).and_return(1)
    @formatter.finish
    $stdout.should include 'errors="1"'
  end

  it "outputs overall error count" do
    @counter.should_receive(:errors).and_return(1)
    @formatter.finish
    $stdout.should include 'errorCount="1"'
  end
end
