require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/file'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

describe FileFormatter, "#register" do
  before :each do
    @formatter = FileFormatter.new
    MSpec.stub(:register)
    MSpec.stub(:unregister)
  end

  it "registers self with MSpec for :load, :unload actions" do
    MSpec.should_receive(:register).with(:load, @formatter)
    MSpec.should_receive(:register).with(:unload, @formatter)
    @formatter.register
  end

  it "unregisters self with MSpec for :before, :after actions" do
    MSpec.should_receive(:unregister).with(:before, @formatter)
    MSpec.should_receive(:unregister).with(:after, @formatter)
    @formatter.register
  end
end

describe FileFormatter, "#load" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
    @formatter = FileFormatter.new
    @formatter.exception ExceptionState.new(nil, nil, SpecExpectationNotMetError.new("Failed!"))
  end

  it "resets the #failure? flag to false" do
    @formatter.failure?.should be_true
    @formatter.load @state
    @formatter.failure?.should be_false
  end

  it "resets the #exception? flag to false" do
    @formatter.exception?.should be_true
    @formatter.load @state
    @formatter.exception?.should be_false
  end
end

describe FileFormatter, "#unload" do
  before :each do
    $stdout = @out = IOStub.new
    @formatter = FileFormatter.new
    @state = ExampleState.new ContextState.new("describe"), "it"
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints a '.' if there was no exception raised" do
    @formatter.unload(@state)
    @out.should == "."
  end

  it "prints an 'F' if there was an expectation failure" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.unload(@state)
    @out.should == "F"
  end

  it "prints an 'E' if there was an exception other than expectation failure" do
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.unload(@state)
    @out.should == "E"
  end

  it "prints an 'E' if there are mixed exceptions and exepctation failures" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.unload(@state)
    @out.should == "E"
  end
end
