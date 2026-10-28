require_relative '../../spec_helper'
require 'coverage'

describe "Coverage.resume" do
  before :all do
    @file = fixture __FILE__, 'sign.rb'
  end

  after :each do
    Coverage.result unless Coverage.state == :idle
  end

  it "returns nil" do
    Coverage.setup
    Coverage.resume.should == nil
  end

  it "starts the coverage measurement that was set up" do
    Coverage.setup
    Coverage.resume
    Coverage.running?.should == true
  end

  it "raises a RuntimeError when the coverage measurement is not set up" do
    -> {
      Coverage.resume
    }.should.raise(RuntimeError, 'coverage measurement is not set up yet')
  end

  it "raises a RuntimeError when the coverage measurement is already running" do
    Coverage.start

    -> {
      Coverage.resume
    }.should.raise(RuntimeError, 'coverage measurement is already running')
  end

  it "counts lines again after the coverage measurement was suspended" do
    Coverage.setup(lines: true)
    load @file
    Coverage.resume
    CoverageSpecs.sign(1)
    Coverage.suspend
    CoverageSpecs.sign(1)
    Coverage.resume
    CoverageSpecs.sign(1)
    Coverage.result[@file][:lines].should == [0, 0, 2, nil, nil]
  end

  it "counts branches again after the coverage measurement was suspended" do
    Coverage.setup(branches: true)
    load @file
    Coverage.resume
    CoverageSpecs.sign(1)
    Coverage.suspend
    CoverageSpecs.sign(1)
    Coverage.resume
    CoverageSpecs.sign(-1)
    Coverage.result[@file][:branches].should == {
      [:if, 0, 3, 4, 3, 33] => {
        [:then, 1, 3, 12, 3, 21] => 1,
        [:else, 2, 3, 24, 3, 33] => 1
      }
    }
  end

  it "counts method calls again after the coverage measurement was suspended" do
    Coverage.setup(methods: true)
    load @file
    Coverage.resume
    CoverageSpecs.sign(1)
    Coverage.suspend
    CoverageSpecs.sign(1)
    Coverage.resume
    CoverageSpecs.sign(1)
    Coverage.result[@file][:methods].should == {
      [CoverageSpecs.singleton_class, :sign, 2, 2, 4, 5] => 2
    }
  end
end
