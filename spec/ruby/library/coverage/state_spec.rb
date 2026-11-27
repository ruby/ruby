require_relative '../../spec_helper'
require 'coverage'

describe "Coverage.state" do
  after :each do
    Coverage.result unless Coverage.state == :idle
  end

  it "returns :idle if coverage is not set up" do
    Coverage.state.should == :idle
  end

  it "returns :suspended if coverage is set up but not started" do
    Coverage.setup
    Coverage.state.should == :suspended
  end

  it "returns :running if coverage is started" do
    Coverage.start
    Coverage.state.should == :running
  end

  it "returns :running if coverage is set up and resumed" do
    Coverage.setup
    Coverage.resume
    Coverage.state.should == :running
  end

  it "returns :suspended if coverage is suspended" do
    Coverage.start
    Coverage.suspend
    Coverage.state.should == :suspended
  end

  it "returns :idle if coverage was started and stopped" do
    Coverage.start
    Coverage.result
    Coverage.state.should == :idle
  end

  it "returns :running if the result was taken without stopping" do
    Coverage.start
    Coverage.result(stop: false)
    Coverage.state.should == :running
  end
end
