require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/dotted'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/utils/script'

describe DottedFormatter, "#initialize" do
  it "permits zero arguments" do
    DottedFormatter.new
  end

  it "accepts one argument" do
    DottedFormatter.new nil
  end
end

describe DottedFormatter, "#register" do
  before :each do
    @formatter = DottedFormatter.new
    MSpec.stub(:register)
  end

  it "registers self with MSpec for appropriate actions" do
    MSpec.should_receive(:register).with(:exception, @formatter)
    MSpec.should_receive(:register).with(:before, @formatter)
    MSpec.should_receive(:register).with(:after, @formatter)
    MSpec.should_receive(:register).with(:finish, @formatter)
    @formatter.register
  end

  it "creates TimerAction and TallyAction" do
    timer = double("timer")
    tally = double("tally")
    timer.should_receive(:register)
    tally.should_receive(:register)
    tally.should_receive(:counter)
    TimerAction.should_receive(:new).and_return(timer)
    TallyAction.should_receive(:new).and_return(tally)
    @formatter.register
  end
end

describe DottedFormatter, "#print" do
  before :each do
    $stdout = IOStub.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "writes to $stdout by default" do
    formatter = DottedFormatter.new
    formatter.print "begonias"
    $stdout.should == "begonias"
  end

  it "writes to the file specified when the formatter was created" do
    out = IOStub.new
    File.should_receive(:open).with("some/file", "w").and_return(out)
    formatter = DottedFormatter.new "some/file"
    formatter.print "begonias"
    out.should == "begonias"
  end

  it "flushes the IO output" do
    $stdout.should_receive(:flush)
    formatter = DottedFormatter.new
    formatter.print "begonias"
  end
end

describe DottedFormatter, "#exception" do
  before :each do
    @formatter = DottedFormatter.new
    @failure = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("failed")
    @error = ExceptionState.new nil, nil, MSpecExampleError.new("boom!")
  end

  it "sets the #failure? flag" do
    @formatter.exception @failure
    @formatter.failure?.should be_true
    @formatter.exception @error
    @formatter.failure?.should be_false
  end

  it "sets the #exception? flag" do
    @formatter.exception @error
    @formatter.exception?.should be_true
    @formatter.exception @failure
    @formatter.exception?.should be_true
  end

  it "adds the exception to the list of exceptions" do
    @formatter.exceptions.should == []
    @formatter.exception @error
    @formatter.exception @failure
    @formatter.exceptions.should == [@error, @failure]
  end
end

describe DottedFormatter, "#exception?" do
  before :each do
    @formatter = DottedFormatter.new
    @failure = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("failed")
    @error = ExceptionState.new nil, nil, MSpecExampleError.new("boom!")
  end

  it "returns false if there have been no exceptions" do
    @formatter.exception?.should be_false
  end

  it "returns true if any exceptions are errors" do
    @formatter.exception @failure
    @formatter.exception @error
    @formatter.exception?.should be_true
  end

  it "returns true if all exceptions are failures" do
    @formatter.exception @failure
    @formatter.exception @failure
    @formatter.exception?.should be_true
  end

  it "returns true if all exceptions are errors" do
    @formatter.exception @error
    @formatter.exception @error
    @formatter.exception?.should be_true
  end
end

describe DottedFormatter, "#failure?" do
  before :each do
    @formatter = DottedFormatter.new
    @failure = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("failed")
    @error = ExceptionState.new nil, nil, MSpecExampleError.new("boom!")
  end

  it "returns false if there have been no exceptions" do
    @formatter.failure?.should be_false
  end

  it "returns false if any exceptions are errors" do
    @formatter.exception @failure
    @formatter.exception @error
    @formatter.failure?.should be_false
  end

  it "returns true if all exceptions are failures" do
    @formatter.exception @failure
    @formatter.exception @failure
    @formatter.failure?.should be_true
  end
end

describe DottedFormatter, "#before" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
    @formatter = DottedFormatter.new
    @formatter.exception ExceptionState.new(nil, nil, SpecExpectationNotMetError.new("Failed!"))
  end

  it "resets the #failure? flag to false" do
    @formatter.failure?.should be_true
    @formatter.before @state
    @formatter.failure?.should be_false
  end

  it "resets the #exception? flag to false" do
    @formatter.exception?.should be_true
    @formatter.before @state
    @formatter.exception?.should be_false
  end
end

describe DottedFormatter, "#after" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = DottedFormatter.new
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints a '.' if there was no exception raised" do
    @formatter.after(@state)
    @out.should == "."
  end

  it "prints an 'F' if there was an expectation failure" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.after(@state)
    @out.should == "F"
  end

  it "prints an 'E' if there was an exception other than expectation failure" do
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.after(@state)
    @out.should == "E"
  end

  it "prints an 'E' if there are mixed exceptions and exepctation failures" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.after(@state)
    @out.should == "E"
  end
end

describe DottedFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    TallyAction.stub(:new).and_return(@tally)
    @timer = double("timer").as_null_object
    TimerAction.stub(:new).and_return(@timer)

    $stdout = @out = IOStub.new
    context = ContextState.new "Class#method"
    @state = ExampleState.new(context, "runs")
    MSpec.stub(:register)
    @formatter = DottedFormatter.new
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
    @out.should =~ /^1\)\nClass#method runs ERROR$/
  end

  it "prints a backtrace for an exception" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
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
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @timer.should_receive(:format).and_return("Finished in 2.0 seconds")
    @tally.should_receive(:format).and_return("1 example, 1 failure")
    @formatter.after @state
    @formatter.finish
    @out.should ==
%[E

1)
Class#method runs ERROR
MSpecExampleError: broken
path/to/some/file.rb:35:in method

Finished in 2.0 seconds

1 example, 1 failure
]
  end
end
