require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/yaml'
require 'mspec/runner/example'
require 'mspec/helpers'

RSpec.describe YamlFormatter, "#initialize" do
  it "permits zero arguments" do
    YamlFormatter.new
  end

  it "accepts one argument" do
    YamlFormatter.new nil
  end
end

RSpec.describe YamlFormatter, "#print" do
  before :each do
    $stdout = IOStub.new
    @out = IOStub.new
    allow(File).to receive(:open).and_return(@out)
    @formatter = YamlFormatter.new "some/file"
  end

  after :each do
    $stdout = STDOUT
  end

  it "writes to $stdout if #switch has not been called" do
    @formatter.print "begonias"
    expect($stdout).to eq("begonias")
    expect(@out).to eq("")
  end

  it "writes to the file passed to #initialize once #switch has been called" do
    @formatter.switch
    @formatter.print "begonias"
    expect($stdout).to eq("")
    expect(@out).to eq("begonias")
  end

  it "writes to $stdout once #switch is called if no file was passed to #initialize" do
    formatter = YamlFormatter.new
    formatter.switch
    formatter.print "begonias"
    expect($stdout).to eq("begonias")
    expect(@out).to eq("")
  end
end

RSpec.describe YamlFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    @counter = double("counter").as_null_object
    allow(@tally).to receive(:counter).and_return(@counter)
    allow(TallyAction).to receive(:new).and_return(@tally)

    @timer = double("timer").as_null_object
    allow(TimerAction).to receive(:new).and_return(@timer)

    @out = tmp("YamlFormatter")

    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")

    @formatter = YamlFormatter.new(@out)
    allow(@formatter).to receive(:backtrace).and_return("")
    allow(MSpec).to receive(:register)
    @formatter.register

    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    allow(exc).to receive(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
  end

  after :each do
    rm_r @out
  end

  it "calls #switch" do
    expect(@formatter).to receive(:switch).and_call_original
    @formatter.finish
  end

  it "outputs a failure message and backtrace" do
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "describe it ERROR"
    expect(output).to include "MSpecExampleError: broken\\n"
    expect(output).to include "path/to/some/file.rb:35:in method"
  end

  it "outputs an elapsed time" do
    expect(@timer).to receive(:elapsed).and_return(4.2)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "time: 4.2"
  end

  it "outputs a file count" do
    expect(@counter).to receive(:files).and_return(3)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "files: 3"
  end

  it "outputs an example count" do
    expect(@counter).to receive(:examples).and_return(3)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "examples: 3"
  end

  it "outputs an expectation count" do
    expect(@counter).to receive(:expectations).and_return(9)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "expectations: 9"
  end

  it "outputs a failure count" do
    expect(@counter).to receive(:failures).and_return(2)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "failures: 2"
  end

  it "outputs an error count" do
    expect(@counter).to receive(:errors).and_return(1)
    @formatter.finish
    output = File.read(@out)
    expect(output).to include "errors: 1"
  end
end
