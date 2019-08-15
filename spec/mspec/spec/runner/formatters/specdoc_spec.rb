require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/specdoc'
require 'mspec/runner/example'

describe SpecdocFormatter do
  before :each do
    @formatter = SpecdocFormatter.new
  end

  it "responds to #register by registering itself with MSpec for appropriate actions" do
    MSpec.stub(:register)
    MSpec.should_receive(:register).with(:enter, @formatter)
    @formatter.register
  end
end

describe SpecdocFormatter, "#enter" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = SpecdocFormatter.new
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints the #describe string" do
    @formatter.enter("describe")
    @out.should == "\ndescribe\n"
  end
end

describe SpecdocFormatter, "#before" do
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
    @out.should == "- it"
  end

  it "resets the #exception? flag" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    @formatter.exception?.should be_true
    @formatter.before @state
    @formatter.exception?.should be_false
  end
end

describe SpecdocFormatter, "#exception" do
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
    @out.should == " (ERROR - 1)"
  end

  it "prints 'FAILED' if an exception is an SpecExpectationNotMetError" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    @out.should == " (FAILED - 1)"
  end

  it "prints the #it string if an exception has already been raised" do
    exc = ExceptionState.new @state, nil, SpecExpectationNotMetError.new("disappointing")
    @formatter.exception exc
    exc = ExceptionState.new @state, nil, MSpecExampleError.new("painful")
    @formatter.exception exc
    @out.should == " (FAILED - 1)\n- it (ERROR - 2)"
  end
end

describe SpecdocFormatter, "#after" do
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
    @out.should == "\n"
  end
end
