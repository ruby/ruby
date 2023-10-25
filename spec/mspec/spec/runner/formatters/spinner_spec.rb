require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/formatters/spinner'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

RSpec.describe SpinnerFormatter, "#initialize" do
  it "permits zero arguments" do
    SpinnerFormatter.new
  end

  it "accepts one argument" do
    SpinnerFormatter.new nil
  end
end

RSpec.describe SpinnerFormatter, "#register" do
  before :each do
    @formatter = SpinnerFormatter.new
    allow(MSpec).to receive(:register)
  end

  it "registers self with MSpec for appropriate actions" do
    expect(MSpec).to receive(:register).with(:start, @formatter)
    expect(MSpec).to receive(:register).with(:unload, @formatter)
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

RSpec.describe SpinnerFormatter, "#print" do
  after :each do
    $stdout = STDOUT
  end

  it "ignores the argument to #initialize and writes to $stdout" do
    $stdout = IOStub.new
    formatter = SpinnerFormatter.new "some/file"
    formatter.print "begonias"
    expect($stdout).to eq("begonias")
  end
end

RSpec.describe SpinnerFormatter, "#after" do
  before :each do
    $stdout = IOStub.new
    MSpec.store(:files, ["a", "b", "c", "d"])
    @formatter = SpinnerFormatter.new
    @formatter.register
    @state = ExampleState.new("describe", "it")
  end

  after :each do
    $stdout = STDOUT
  end

  it "updates the spinner" do
    @formatter.start
    @formatter.after @state
    @formatter.unload

    if ENV["TERM"] != "dumb"
      green = "\e[0;32m"
      reset = "\e[0m"
    end

    output = "\r[/ |                   0%                     | 00:00:00] #{green}     0F #{green}     0E#{reset} " \
             "\r[- |                   0%                     | 00:00:00] #{green}     0F #{green}     0E#{reset} " \
            "\r[\\ | ==========        25%                    | 00:00:00] #{green}     0F #{green}     0E#{reset} "
    expect($stdout).to eq(output)
  end
end
