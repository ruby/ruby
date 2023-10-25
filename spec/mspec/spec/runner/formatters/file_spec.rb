require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/file'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

RSpec.describe FileFormatter, "#register" do
  before :each do
    @formatter = FileFormatter.new
    allow(MSpec).to receive(:register)
    allow(MSpec).to receive(:unregister)
  end

  it "registers self with MSpec for :load, :unload actions" do
    expect(MSpec).to receive(:register).with(:load, @formatter)
    expect(MSpec).to receive(:register).with(:unload, @formatter)
    @formatter.register
  end

  it "unregisters self with MSpec for :before, :after actions" do
    expect(MSpec).to receive(:unregister).with(:before, @formatter)
    expect(MSpec).to receive(:unregister).with(:after, @formatter)
    @formatter.register
  end
end

RSpec.describe FileFormatter, "#load" do
  before :each do
    @state = ExampleState.new ContextState.new("describe"), "it"
    @formatter = FileFormatter.new
    @formatter.exception ExceptionState.new(nil, nil, SpecExpectationNotMetError.new("Failed!"))
  end

  it "resets the #failure? flag to false" do
    expect(@formatter.failure?).to be_truthy
    @formatter.load @state
    expect(@formatter.failure?).to be_falsey
  end

  it "resets the #exception? flag to false" do
    expect(@formatter.exception?).to be_truthy
    @formatter.load @state
    expect(@formatter.exception?).to be_falsey
  end
end

RSpec.describe FileFormatter, "#unload" do
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
    expect(@out).to eq(".")
  end

  it "prints an 'F' if there was an expectation failure" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.unload(@state)
    expect(@out).to eq("F")
  end

  it "prints an 'E' if there was an exception other than expectation failure" do
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.unload(@state)
    expect(@out).to eq("E")
  end

  it "prints an 'E' if there are mixed exceptions and exepctation failures" do
    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    exc = MSpecExampleError.new("boom!")
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.unload(@state)
    expect(@out).to eq("E")
  end
end
