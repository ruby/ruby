require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/method'
require 'mspec/runner/mspec'
require 'mspec/runner/example'
require 'mspec/utils/script'

describe MethodFormatter, "#method_type" do
  before :each do
    @formatter = MethodFormatter.new
  end

  it "returns 'class' if the separator is '.' or '::'" do
    @formatter.method_type('.').should == "class"
    @formatter.method_type('::').should == "class"
  end

  it "returns 'instance' if the separator is '#'" do
    @formatter.method_type('#').should == "instance"
  end

  it "returns 'unknown' for all other cases" do
    @formatter.method_type(nil).should == "unknown"
  end
end

describe MethodFormatter, "#before" do
  before :each do
    @formatter = MethodFormatter.new
    MSpec.stub(:register)
    @formatter.register
  end

  it "resets the tally counters to 0" do
    @formatter.tally.counter.examples = 3
    @formatter.tally.counter.expectations = 4
    @formatter.tally.counter.failures = 2
    @formatter.tally.counter.errors = 1

    state = ExampleState.new ContextState.new("describe"), "it"
    @formatter.before state
    @formatter.tally.counter.examples.should == 0
    @formatter.tally.counter.expectations.should == 0
    @formatter.tally.counter.failures.should == 0
    @formatter.tally.counter.errors.should == 0
  end

  it "records the class, method if available" do
    state = ExampleState.new ContextState.new("Some#method"), "it"
    @formatter.before state
    key = "Some#method"
    @formatter.methods.keys.should include(key)
    h = @formatter.methods[key]
    h[:class].should == "Some"
    h[:method].should == "method"
    h[:description].should == "Some#method it"
  end

  it "does not record class, method unless both are available" do
    state = ExampleState.new ContextState.new("Some method"), "it"
    @formatter.before state
    key = "Some method"
    @formatter.methods.keys.should include(key)
    h = @formatter.methods[key]
    h[:class].should == ""
    h[:method].should == ""
    h[:description].should == "Some method it"
  end

  it "sets the method type to unknown if class and method are not available" do
    state = ExampleState.new ContextState.new("Some method"), "it"
    @formatter.before state
    key = "Some method"
    h = @formatter.methods[key]
    h[:type].should == "unknown"
  end

  it "sets the method type based on the class, method separator" do
    [["C#m", "instance"], ["C.m", "class"], ["C::m", "class"]].each do |k, t|
      state = ExampleState.new ContextState.new(k), "it"
      @formatter.before state
      h = @formatter.methods[k]
      h[:type].should == t
    end
  end

  it "clears the list of exceptions" do
    state = ExampleState.new ContextState.new("describe"), "it"
    @formatter.exceptions << "stuff"
    @formatter.before state
    @formatter.exceptions.should be_empty
  end
end

describe MethodFormatter, "#after" do
  before :each do
    @formatter = MethodFormatter.new
    MSpec.stub(:register)
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
    h[:examples].should == 3
    h[:expectations].should == 4
    h[:failures].should == 2
    h[:errors].should == 1
  end

  it "renders the list of exceptions" do
    state = ExampleState.new ContextState.new("Some#method"), "it"
    @formatter.before state

    exc = SpecExpectationNotMetError.new "failed"
    @formatter.exception ExceptionState.new(state, nil, exc)
    @formatter.exception ExceptionState.new(state, nil, exc)

    @formatter.after state
    h = @formatter.methods["Some#method"]
    h[:exceptions].should == [
      %[failed\n\n],
      %[failed\n\n]
    ]
  end
end

describe MethodFormatter, "#after" do
  before :each do
    $stdout = IOStub.new
    context = ContextState.new "Class#method"
    @state = ExampleState.new(context, "runs")
    @formatter = MethodFormatter.new
    MSpec.stub(:register)
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
    $stdout.should ==
%[---
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
]
  end
end
