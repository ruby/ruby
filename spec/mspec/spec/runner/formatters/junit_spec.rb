# -*- coding: utf-8 -*-
require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/junit'
require 'mspec/runner/example'
require 'mspec/helpers'

RSpec.describe JUnitFormatter, "#initialize" do
  it "permits zero arguments" do
    expect { JUnitFormatter.new }.not_to raise_error
  end

  it "accepts one argument" do
    expect { JUnitFormatter.new nil }.not_to raise_error
  end
end

RSpec.describe JUnitFormatter, "#print" do
  before :each do
    $stdout = IOStub.new
    @out = IOStub.new
    allow(File).to receive(:open).and_return(@out)
    @formatter = JUnitFormatter.new "some/file"
  end

  after :each do
    $stdout = STDOUT
  end

  it "writes to $stdout if #switch has not been called" do
    @formatter.print "begonias"
    expect($stdout).to eq("begonias")
    expect(@out).to eq("")
  end

  it "writes to the file passed to #initialize once #switch has been called" do
    @formatter.switch
    @formatter.print "begonias"
    expect($stdout).to eq("")
    expect(@out).to eq("begonias")
  end

  it "writes to $stdout once #switch is called if no file was passed to #initialize" do
    formatter = JUnitFormatter.new
    formatter.switch
    formatter.print "begonias"
    expect($stdout).to eq("begonias")
    expect(@out).to eq("")
  end
end

RSpec.describe JUnitFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    @counter = double("counter").as_null_object
    allow(@tally).to receive(:counter).and_return(@counter)
    allow(TallyAction).to receive(:new).and_return(@tally)

    @timer = double("timer").as_null_object
    allow(TimerAction).to receive(:new).and_return(@timer)

    @out = tmp("JUnitFormatter")

    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")

    @formatter = JUnitFormatter.new(@out)
    allow(@formatter).to receive(:backtrace).and_return("")
    allow(MSpec).to receive(:register)
    @formatter.register

    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
  end

  after :each do
    rm_r @out
  end

  it "calls #switch" do
    expect(@formatter).to receive(:switch).and_call_original
    @formatter.finish
  end

  it "outputs a failure message and backtrace" do
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'message="error in describe it" type="error"'
    expect(output).to include "MSpecExampleError: broken\n"
    expect(output).to include "path/to/some/file.rb:35:in method"
  end

  it "encodes message and backtrace in latin1 for jenkins" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken…")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in methød")
    @formatter.exception exc
    @formatter.finish
    output = File.binread(@out)
    expect(output).to match(/MSpecExampleError: broken((\.\.\.)|\?)\n/)
    expect(output).to match(/path\/to\/some\/file\.rb:35:in meth(\?|o)d/)
  end

  it "outputs an elapsed time" do
    expect(@timer).to receive(:elapsed).and_return(4.2)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'time="4.2"'
  end

  it "outputs overall elapsed time" do
    expect(@timer).to receive(:elapsed).and_return(4.2)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'timeCount="4.2"'
  end

  it "outputs the number of examples as test count" do
    expect(@counter).to receive(:examples).and_return(9)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'tests="9"'
  end

  it "outputs overall number of examples as test count" do
    expect(@counter).to receive(:examples).and_return(9)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'testCount="9"'
  end

  it "outputs a failure count" do
    expect(@counter).to receive(:failures).and_return(2)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'failureCount="2"'
  end

  it "outputs overall failure count" do
    expect(@counter).to receive(:failures).and_return(2)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'failures="2"'
  end

  it "outputs an error count" do
    expect(@counter).to receive(:errors).and_return(1)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'errors="1"'
  end

  it "outputs overall error count" do
    expect(@counter).to receive(:errors).and_return(1)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include 'errorCount="1"'
  end
end
