require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/describe'
require 'mspec/runner/example'

RSpec.describe DescribeFormatter, "#finish" do
  before :each do
    allow(MSpec).to receive(:register)
    allow(MSpec).to receive(:unregister)

    @timer = double("timer").as_null_object
    allow(TimerAction).to receive(:new).and_return(@timer)
    allow(@timer).to receive(:format).and_return("Finished in 2.0 seconds")

    $stdout = @out = IOStub.new
    context = ContextState.new "Class#method"
    @state = ExampleState.new(context, "runs")

    @formatter = DescribeFormatter.new
    @formatter.register

    @tally = @formatter.tally
    @counter = @tally.counter

    @counter.files!
    @counter.examples!
    @counter.expectations! 2
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints a summary of elapsed time" do
    @formatter.finish
    expect(@out).to match(/^Finished in 2.0 seconds$/)
  end

  it "prints a tally of counts" do
    @formatter.finish
    expect(@out).to match(/^1 file, 1 example, 2 expectations, 0 failures, 0 errors, 0 tagged$/)
  end

  it "does not print exceptions" do
    @formatter.finish
    expect(@out).to eq(%[

Finished in 2.0 seconds

1 file, 1 example, 2 expectations, 0 failures, 0 errors, 0 tagged
])
  end

  it "prints a summary of failures and errors for each describe block" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.finish
    expect(@out).to eq(%[

Class#method                             0 failures, 1 error

Finished in 2.0 seconds

1 file, 1 example, 2 expectations, 0 failures, 0 errors, 0 tagged
])
  end
end
