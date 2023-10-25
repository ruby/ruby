require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/method'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/utils/script'

RSpec.describe MethodFormatter, "#method_type" do
  before :each do
    @formatter = MethodFormatter.new
  end

  it "returns 'class' if the separator is '.' or '::'" do
    expect(@formatter.method_type('.')).to eq("class")
    expect(@formatter.method_type('::')).to eq("class")
  end

  it "returns 'instance' if the separator is '#'" do
    expect(@formatter.method_type('#')).to eq("instance")
  end

  it "returns 'unknown' for all other cases" do
    expect(@formatter.method_type(nil)).to eq("unknown")
  end
end

RSpec.describe MethodFormatter, "#before" do
  before :each do
    @formatter = MethodFormatter.new
    allow(MSpec).to receive(:register)
    @formatter.register
  end

  it "resets the tally counters to 0" do
    @formatter.tally.counter.examples = 3
    @formatter.tally.counter.expectations = 4
    @formatter.tally.counter.failures = 2
    @formatter.tally.counter.errors = 1

    state = ExampleState.new ContextState.new("describe"), "it"
    @formatter.before state
    expect(@formatter.tally.counter.examples).to eq(0)
    expect(@formatter.tally.counter.expectations).to eq(0)
    expect(@formatter.tally.counter.failures).to eq(0)
    expect(@formatter.tally.counter.errors).to eq(0)
  end

  it "records the class, method if available" do
    state = ExampleState.new ContextState.new("Some#method"), "it"
    @formatter.before state
    key = "Some#method"
    expect(@formatter.methods.keys).to include(key)
    h = @formatter.methods[key]
    expect(h[:class]).to eq("Some")
    expect(h[:method]).to eq("method")
    expect(h[:description]).to eq("Some#method it")
  end

  it "does not record class, method unless both are available" do
    state = ExampleState.new ContextState.new("Some method"), "it"
    @formatter.before state
    key = "Some method"
    expect(@formatter.methods.keys).to include(key)
    h = @formatter.methods[key]
    expect(h[:class]).to eq("")
    expect(h[:method]).to eq("")
    expect(h[:description]).to eq("Some method it")
  end

  it "sets the method type to unknown if class and method are not available" do
    state = ExampleState.new ContextState.new("Some method"), "it"
    @formatter.before state
    key = "Some method"
    h = @formatter.methods[key]
    expect(h[:type]).to eq("unknown")
  end

  it "sets the method type based on the class, method separator" do
    [["C#m", "instance"], ["C.m", "class"], ["C::m", "class"]].each do |k, t|
      state = ExampleState.new ContextState.new(k), "it"
      @formatter.before state
      h = @formatter.methods[k]
      expect(h[:type]).to eq(t)
    end
  end

  it "clears the list of exceptions" do
    state = ExampleState.new ContextState.new("describe"), "it"
    @formatter.exceptions << "stuff"
    @formatter.before state
    expect(@formatter.exceptions).to be_empty
  end
end

RSpec.describe MethodFormatter, "#after" do
  before :each do
    @formatter = MethodFormatter.new
    allow(MSpec).to receive(:register)
    @formatter.register
  end

  it "sets the tally counts" do
    state = ExampleState.new ContextState.new("Some#method"), "it"
    @formatter.before state

    @formatter.tally.counter.examples = 3
    @formatter.tally.counter.expectations = 4
    @formatter.tally.counter.failures = 2
    @formatter.tally.counter.errors = 1

    @formatter.after state
    h = @formatter.methods["Some#method"]
    expect(h[:examples]).to eq(3)
    expect(h[:expectations]).to eq(4)
    expect(h[:failures]).to eq(2)
    expect(h[:errors]).to eq(1)
  end

  it "renders the list of exceptions" do
    state = ExampleState.new ContextState.new("Some#method"), "it"
    @formatter.before state

    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(state, nil, exc)
    @formatter.exception ExceptionState.new(state, nil, exc)

    @formatter.after state
    h = @formatter.methods["Some#method"]
    expect(h[:exceptions]).to eq([
      %[failed\n\n],
      %[failed\n\n]
    ])
  end
end

RSpec.describe MethodFormatter, "#after" do
  before :each do
    $stdout = IOStub.new
    context = ContextState.new "Class#method"
    @state = ExampleState.new(context, "runs")
    @formatter = MethodFormatter.new
    allow(MSpec).to receive(:register)
    @formatter.register
  end

  after :each do
    $stdout = STDOUT
  end

  it "prints a summary of the results of an example in YAML format" do
    @formatter.before @state
    @formatter.tally.counter.examples = 3
    @formatter.tally.counter.expectations = 4
    @formatter.tally.counter.failures = 2
    @formatter.tally.counter.errors = 1

    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(@state, nil, exc)
    @formatter.exception ExceptionState.new(@state, nil, exc)

    @formatter.after @state
    @formatter.finish
    expect($stdout).to eq(%[---
"Class#method":
  class: "Class"
  method: "method"
  type: instance
  description: "Class#method runs"
  examples: 3
  expectations: 4
  failures: 2
  errors: 1
  exceptions:
  - "failed\\n\\n"
  - "failed\\n\\n"
])
  end
end
