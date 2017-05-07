require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/unit'
require 'mspec/runner/example'
require 'mspec/utils/script'

describe UnitdiffFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    TallyAction.stub(:new).and_return(@tally)
    @timer = double("timer").as_null_object
    TimerAction.stub(:new).and_return(@timer)

    $stdout = @out = IOStub.new
    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")
    MSpec.stub(:register)
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
    @out.should =~ /^1\)\ndescribe it ERROR$/
  end

  it "prints a backtrace for an exception" do
    exc = ExceptionState.new @state, nil, Exception.new("broken")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.finish
    @out.should =~ %r[path/to/some/file.rb:35:in method$]
  end

  it "prints a summary of elapsed time" do
    @timer.should_receive(:format).and_return("Finished in 2.0 seconds")
    @formatter.finish
    @out.should =~ /^Finished in 2.0 seconds$/
  end

  it "prints a tally of counts" do
    @tally.should_receive(:format).and_return("1 example, 0 failures")
    @formatter.finish
    @out.should =~ /^1 example, 0 failures$/
  end

  it "prints errors, backtraces, elapsed time, and tallies" do
    exc = ExceptionState.new @state, nil, Exception.new("broken")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
    @timer.should_receive(:format).and_return("Finished in 2.0 seconds")
    @tally.should_receive(:format).and_return("1 example, 0 failures")
    @formatter.finish
    @out.should ==
%[E

Finished in 2.0 seconds

1)
describe it ERROR
Exception: broken:
path/to/some/file.rb:35:in method

1 example, 0 failures
]
  end
end
