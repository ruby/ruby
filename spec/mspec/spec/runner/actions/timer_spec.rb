require File.dirname(__FILE__) + '/../../spec_helper'
require 'mspec/runner/actions/timer'
require 'mspec/runner/mspec'
require 'time'

RSpec.describe TimerAction do
  before :each do
    @timer = TimerAction.new
    @start_time = Time.utc(2009, 3, 30, 14, 5, 19)
    @stop_time  = Time.utc(2009, 3, 30, 14, 5, 52)
  end

  it "responds to #start by recording the current time" do
    expect(Time).to receive(:now)
    @timer.start
  end

  it "responds to #finish by recording the current time" do
    expect(Time).to receive(:now)
    @timer.finish
  end

  it "responds to #elapsed by returning the difference between stop and start" do
    allow(Time).to receive(:now).and_return(@start_time)
    @timer.start
    allow(Time).to receive(:now).and_return(@stop_time)
    @timer.finish
    expect(@timer.elapsed).to eq(33)
  end

  it "responds to #format by returning a readable string of elapsed time" do
    allow(Time).to receive(:now).and_return(@start_time)
    @timer.start
    allow(Time).to receive(:now).and_return(@stop_time)
    @timer.finish
    expect(@timer.format).to eq("Finished in 33.000000 seconds")
  end

  it "responds to #register by registering itself with MSpec for appropriate actions" do
    expect(MSpec).to receive(:register).with(:start, @timer)
    expect(MSpec).to receive(:register).with(:finish, @timer)
    @timer.register
  end
end
