require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/specdoc'
require 'mspec/runner/example'

RSpec.describe SpecdocFormatter do
  before :each do
    @formatter = SpecdocFormatter.new
  end

  it "responds to #register by registering itself with MSpec for appropriate actions" do
    allow(MSpec).to receive(:register)
    expect(MSpec).to receive(:register).with(:enter, @formatter)
    @formatter.register
  end
end

RSpec.describe SpecdocFormatter, "#enter" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = SpecdocFormatter.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the #describe string" do
    @formatter.enter("describe")
    expect(@out).to eq("\ndescribe\n")
  end
end

RSpec.describe SpecdocFormatter, "#before" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = SpecdocFormatter.new
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the #it string" do
    @formatter.before @state
    expect(@out).to eq("- it")
  end

  it "resets the #exception? flag" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    expect(@formatter.exception?).to be_truthy
    @formatter.before @state
    expect(@formatter.exception?).to be_falsey
  end
end

RSpec.describe SpecdocFormatter, "#exception" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = SpecdocFormatter.new
    context = ContextState.new "describe"
    @state = ExampleState.new context, "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints 'ERROR' if an exception is not an SpecExpectationNotMetError" do
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("painful")
    @formatter.exception exc
    expect(@out).to eq(" (ERROR - 1)")
  end

  it "prints 'FAILED' if an exception is an SpecExpectationNotMetError" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    expect(@out).to eq(" (FAILED - 1)")
  end

  it "prints the #it string if an exception has already been raised" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("painful")
    @formatter.exception exc
    expect(@out).to eq(" (FAILED - 1)\n- it (ERROR - 2)")
  end
end

RSpec.describe SpecdocFormatter, "#after" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = SpecdocFormatter.new
    @state = ExampleState.new "describe", "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints a newline character" do
    @formatter.after @state
    expect(@out).to eq("\n")
  end
end
