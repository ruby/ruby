require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/dotted'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/utils/script'

RSpec.describe DottedFormatter, "#initialize" do
  it "permits zero arguments" do
    DottedFormatter.new
  end

  it "accepts one argument" do
    DottedFormatter.new nil
  end
end

RSpec.describe DottedFormatter, "#register" do
  before :each do
    @formatter = DottedFormatter.new
    allow(MSpec).to receive(:register)
  end

  it "registers self with MSpec for appropriate actions" do
    expect(MSpec).to receive(:register).with(:exception, @formatter)
    expect(MSpec).to receive(:register).with(:before, @formatter)
    expect(MSpec).to receive(:register).with(:after, @formatter)
    expect(MSpec).to receive(:register).with(:finish, @formatter)
    @formatter.register
  end

  it "creates TimerAction and TallyAction" do
    timer = double("timer")
    tally = double("tally")
    expect(timer).to receive(:register)
    expect(tally).to receive(:register)
    expect(tally).to receive(:counter)
    expect(TimerAction).to receive(:new).and_return(timer)
    expect(TallyAction).to receive(:new).and_return(tally)
    @formatter.register
  end
end

RSpec.describe DottedFormatter, "#print" do
  before :each do
    $stdout = IOStub.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "writes to $stdout by default" do
    formatter = DottedFormatter.new
    formatter.print "begonias"
    expect($stdout).to eq("begonias")
  end

  it "writes to the file specified when the formatter was created" do
    out = IOStub.new
    expect(File).to receive(:open).with("some/file", "w").and_return(out)
    formatter = DottedFormatter.new "some/file"
    formatter.print "begonias"
    expect(out).to eq("begonias")
  end

  it "flushes the IO output" do
    expect($stdout).to receive(:flush)
    formatter = DottedFormatter.new
    formatter.print "begonias"
  end
end

RSpec.describe DottedFormatter, "#exception" do
  before :each do
    @formatter = DottedFormatter.new
    @failure = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("failed")
    @error = ExceptionState.new nil, nil, MSpecExampleError.new("boom!")
  end

  it "sets the #failure? flag" do
    @formatter.exception @failure
    expect(@formatter.failure?).to be_truthy
    @formatter.exception @error
    expect(@formatter.failure?).to be_falsey
  end

  it "sets the #exception? flag" do
    @formatter.exception @error
    expect(@formatter.exception?).to be_truthy
    @formatter.exception @failure
    expect(@formatter.exception?).to be_truthy
  end

  it "adds the exception to the list of exceptions" do
    expect(@formatter.exceptions).to eq([])
    @formatter.exception @error
    @formatter.exception @failure
    expect(@formatter.exceptions).to eq([@error, @failure])
  end
end

RSpec.describe DottedFormatter, "#exception?" do
  before :each do
    @formatter = DottedFormatter.new
    @failure = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("failed")
    @error = ExceptionState.new nil, nil, MSpecExampleError.new("boom!")
  end

  it "returns false if there have been no exceptions" do
    expect(@formatter.exception?).to be_falsey
  end

  it "returns true if any exceptions are errors" do
    @formatter.exception @failure
    @formatter.exception @error
    expect(@formatter.exception?).to be_truthy
  end

  it "returns true if all exceptions are failures" do
    @formatter.exception @failure
    @formatter.exception @failure
    expect(@formatter.exception?).to be_truthy
  end

  it "returns true if all exceptions are errors" do
    @formatter.exception @error
    @formatter.exception @error
    expect(@formatter.exception?).to be_truthy
  end
end

RSpec.describe DottedFormatter, "#failure?" do
  before :each do
    @formatter = DottedFormatter.new
    @failure = ExceptionState.new nil, nil, SpecExpectationNotMetError.new("failed")
    @error = ExceptionState.new nil, nil, MSpecExampleError.new("boom!")
  end

  it "returns false if there have been no exceptions" do
    expect(@formatter.failure?).to be_falsey
  end

  it "returns false if any exceptions are errors" do
    @formatter.exception @failure
    @formatter.exception @error
    expect(@formatter.failure?).to be_falsey
  end

  it "returns true if all exceptions are failures" do
    @formatter.exception @failure
    @formatter.exception @failure
    expect(@formatter.failure?).to be_truthy
  end
end

RSpec.describe DottedFormatter, "#before" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
    @formatter = DottedFormatter.new
    @formatter.exception ExceptionState.new(nil, nil, SpecExpectationNotMetError.new("Failed!"))
  end

  it "resets the #failure? flag to false" do
    expect(@formatter.failure?).to be_truthy
    @formatter.before @state
    expect(@formatter.failure?).to be_falsey
  end

  it "resets the #exception? flag to false" do
    expect(@formatter.exception?).to be_truthy
    @formatter.before @state
    expect(@formatter.exception?).to be_falsey
  end
end

RSpec.describe DottedFormatter, "#after" do
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
    expect(@out).to eq(".")
  end

  it "prints an 'F' if there was an expectation failure" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.after(@state)
    expect(@out).to eq("F")
  end

  it "prints an 'E' if there was an exception other than expectation failure" do
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.after(@state)
    expect(@out).to eq("E")
  end

  it "prints an 'E' if there are mixed exceptions and exepctation failures" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.after(@state)
    expect(@out).to eq("E")
  end
end

RSpec.describe DottedFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    allow(TallyAction).to receive(:new).and_return(@tally)
    @timer = double("timer").as_null_object
    allow(TimerAction).to receive(:new).and_return(@timer)

    $stdout = @out = IOStub.new
    context = ContextState.new "Class#method"
    @state = ExampleState.new(context, "runs")
    allow(MSpec).to receive(:register)
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
    expect(@out).to match(/^1\)\nClass#method runs ERROR$/)
  end

  it "prints a backtrace for an exception" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
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
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    expect(@timer).to receive(:format).and_return("Finished in 2.0 seconds")
    expect(@tally).to receive(:format).and_return("1 example, 1 failure")
    @formatter.after @state
    @formatter.finish
    expect(@out).to eq(%[E

1)
Class#method runs ERROR
MSpecExampleError: broken
path/to/some/file.rb:35:in method

Finished in 2.0 seconds

1 example, 1 failure
])
  end
end
