require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/runner/example'
require 'mspec/runner/exception'
require 'mspec/utils/script'

RSpec.describe ExceptionState, "#initialize" do
  it "takes a state, location (e.g. before :each), and exception" do
    context = ContextState.new "Class#method"
    state = ExampleState.new context, "does something"
    exc = Exception.new "Fail!"
    expect(ExceptionState.new(state, "location", exc)).to be_kind_of(ExceptionState)
  end
end

RSpec.describe ExceptionState, "#description" do
  before :each do
    context = ContextState.new "Class#method"
    @state = ExampleState.new context, "does something"
  end

  it "returns the state description if state was not nil" do
    exc = ExceptionState.new(@state, nil, nil)
    expect(exc.description).to eq("Class#method does something")
  end

  it "returns the location if it is not nil and description is nil" do
    exc = ExceptionState.new(nil, "location", nil)
    expect(exc.description).to eq("An exception occurred during: location")
  end

  it "returns both description and location if neither are nil" do
    exc = ExceptionState.new(@state, "location", nil)
    expect(exc.description).to eq("An exception occurred during: location\nClass#method does something")
  end
end

RSpec.describe ExceptionState, "#describe" do
  before :each do
    context = ContextState.new "Class#method"
    @state = ExampleState.new context, "does something"
  end

  it "returns the ExampleState#describe string if created with a non-nil state" do
    expect(ExceptionState.new(@state, nil, nil).describe).to eq(@state.describe)
  end

  it "returns an empty string if created with a nil state" do
    expect(ExceptionState.new(nil, nil, nil).describe).to eq("")
  end
end

RSpec.describe ExceptionState, "#it" do
  before :each do
    context = ContextState.new "Class#method"
    @state = ExampleState.new context, "does something"
  end

  it "returns the ExampleState#it string if created with a non-nil state" do
    expect(ExceptionState.new(@state, nil, nil).it).to eq(@state.it)
  end

  it "returns an empty string if created with a nil state" do
    expect(ExceptionState.new(nil, nil, nil).it).to eq("")
  end
end

RSpec.describe ExceptionState, "#failure?" do
  before :each do
    @state = ExampleState.new ContextState.new("C#m"), "works"
  end

  it "returns true if the exception is an SpecExpectationNotMetError" do
    exc = ExceptionState.new @state, "", SpecExpectationNotMetError.new("Fail!")
    expect(exc.failure?).to be_truthy
  end

  it "returns true if the exception is an SpecExpectationNotFoundError" do
    exc = ExceptionState.new @state, "", SpecExpectationNotFoundError.new("Fail!")
    expect(exc.failure?).to be_truthy
  end

  it "returns false if the exception is not an SpecExpectationNotMetError or an SpecExpectationNotFoundError" do
    exc = ExceptionState.new @state, "", Exception.new("Fail!")
    expect(exc.failure?).to be_falsey
  end
end

RSpec.describe ExceptionState, "#message" do
  before :each do
    @state = ExampleState.new ContextState.new("C#m"), "works"
  end

  it "returns <No message> if the exception message is empty" do
    exc = ExceptionState.new @state, "", Exception.new("")
    expect(exc.message).to eq("Exception: <No message>")
  end

  it "returns the message without exception class when the exception is an SpecExpectationNotMetError" do
    exc = ExceptionState.new @state, "", SpecExpectationNotMetError.new("Fail!")
    expect(exc.message).to eq("Fail!")
  end

  it "returns SpecExpectationNotFoundError#message when the exception is an SpecExpectationNotFoundError" do
    e = SpecExpectationNotFoundError.new
    exc = ExceptionState.new @state, "", e
    expect(exc.message).to eq(e.message)
  end

  it "returns the message with exception class when the exception is not an SpecExpectationNotMetError or an SpecExpectationNotFoundError" do
    exc = ExceptionState.new @state, "", Exception.new("Fail!")
    expect(exc.message).to eq("Exception: Fail!")
  end
end

RSpec.describe ExceptionState, "#backtrace" do
  before :each do
    @state = ExampleState.new ContextState.new("C#m"), "works"
    begin
      raise Exception
    rescue Exception => @exception
      @exc = ExceptionState.new @state, "", @exception
    end
  end

  after :each do
    $MSPEC_DEBUG = nil
  end

  it "returns a string representation of the exception backtrace" do
    expect(@exc.backtrace).to be_kind_of(String)
  end

  it "does not filter files from the backtrace if $MSPEC_DEBUG is true" do
    $MSPEC_DEBUG = true
    expect(@exc.backtrace).to eq(@exception.backtrace.join("\n"))
  end

  it "filters files matching config[:backtrace_filter]" do
    MSpecScript.set :backtrace_filter, %r[mspec/lib]
    $MSPEC_DEBUG = nil
    @exc.backtrace.split("\n").each do |line|
      expect(line).not_to match(%r[mspec/lib])
    end
  end
end
