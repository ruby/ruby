require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/unit'
require 'mspec/runner/example'
require 'mspec/utils/script'

RSpec.describe UnitdiffFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    allow(TallyAction).to receive(:new).and_return(@tally)
    @timer = double("timer").as_null_object
    allow(TimerAction).to receive(:new).and_return(@timer)

    $stdout = @out = IOStub.new
    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")
    allow(MSpec).to receive(:register)
    @formatter = UnitdiffFormatter.new
    @formatter.register
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints a failure message for an exception" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    @formatter.exception exc
    @formatter.after @state
    @formatter.finish
    expect(@out).to match(/^1\)\ndescribe it ERROR$/)
  end

  it "prints a backtrace for an exception" do
    exc = ExceptionState.new @state, nil, Exception.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.finish
    expect(@out).to match(%r[path/to/some/file.rb:35:in method$])
  end

  it "prints a summary of elapsed time" do
    expect(@timer).to receive(:format).and_return("Finished in 2.0 seconds")
    @formatter.finish
    expect(@out).to match(/^Finished in 2.0 seconds$/)
  end

  it "prints a tally of counts" do
    expect(@tally).to receive(:format).and_return("1 example, 0 failures")
    @formatter.finish
    expect(@out).to match(/^1 example, 0 failures$/)
  end

  it "prints errors, backtraces, elapsed time, and tallies" do
    exc = ExceptionState.new @state, nil, Exception.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
    expect(@timer).to receive(:format).and_return("Finished in 2.0 seconds")
    expect(@tally).to receive(:format).and_return("1 example, 0 failures")
    @formatter.finish
    expect(@out).to eq(%[E

Finished in 2.0 seconds

1)
describe it ERROR
Exception: broken:
path/to/some/file.rb:35:in method

1 example, 0 failures
])
  end
end
