require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/yaml'
require 'mspec/runner/example'

describe YamlFormatter, "#initialize" do
  it "permits zero arguments" do
    YamlFormatter.new
  end

  it "accepts one argument" do
    YamlFormatter.new nil
  end
end

describe YamlFormatter, "#print" do
  before :each do
    $stdout = IOStub.new
    @out = IOStub.new
    File.stub(:open).and_return(@out)
    @formatter = YamlFormatter.new "some/file"
  end

  after :each do
    $stdout = STDOUT
  end

  it "writes to $stdout if #switch has not been called" do
    @formatter.print "begonias"
    $stdout.should == "begonias"
    @out.should == ""
  end

  it "writes to the file passed to #initialize once #switch has been called" do
    @formatter.switch
    @formatter.print "begonias"
    $stdout.should == ""
    @out.should == "begonias"
  end

  it "writes to $stdout once #switch is called if no file was passed to #initialize" do
    formatter = YamlFormatter.new
    formatter.switch
    formatter.print "begonias"
    $stdout.should == "begonias"
    @out.should == ""
  end
end

describe YamlFormatter, "#finish" do
  before :each do
    @tally = double("tally").as_null_object
    @counter = double("counter").as_null_object
    @tally.stub(:counter).and_return(@counter)
    TallyAction.stub(:new).and_return(@tally)

    @timer = double("timer").as_null_object
    TimerAction.stub(:new).and_return(@timer)

    $stdout = IOStub.new
    context = ContextState.new "describe"
    @state = ExampleState.new(context, "it")

    @formatter = YamlFormatter.new
    @formatter.stub(:backtrace).and_return("")
    MSpec.stub(:register)
    @formatter.register

    exc = ExceptionState.new @state, nil, MSpecExampleError.new("broken")
    exc.stub(:backtrace).and_return("path/to/some/file.rb:35:in method")
    @formatter.exception exc
    @formatter.after @state
  end

  after :each do
    $stdout = STDOUT
  end

  it "calls #switch" do
    @formatter.should_receive(:switch)
    @formatter.finish
  end

  it "outputs a failure message and backtrace" do
    @formatter.finish
    $stdout.should include "describe it ERROR"
    $stdout.should include "MSpecExampleError: broken\\n"
    $stdout.should include "path/to/some/file.rb:35:in method"
  end

  it "outputs an elapsed time" do
    @timer.should_receive(:elapsed).and_return(4.2)
    @formatter.finish
    $stdout.should include "time: 4.2"
  end

  it "outputs a file count" do
    @counter.should_receive(:files).and_return(3)
    @formatter.finish
    $stdout.should include "files: 3"
  end

  it "outputs an example count" do
    @counter.should_receive(:examples).and_return(3)
    @formatter.finish
    $stdout.should include "examples: 3"
  end

  it "outputs an expectation count" do
    @counter.should_receive(:expectations).and_return(9)
    @formatter.finish
    $stdout.should include "expectations: 9"
  end

  it "outputs a failure count" do
    @counter.should_receive(:failures).and_return(2)
    @formatter.finish
    $stdout.should include "failures: 2"
  end

  it "outputs an error count" do
    @counter.should_receive(:errors).and_return(1)
    @formatter.finish
    $stdout.should include "errors: 1"
  end
end
