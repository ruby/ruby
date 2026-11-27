require_relative '../../spec_helper'
require 'coverage'

describe "Coverage.suspend" do
  before :all do
    @file = fixture __FILE__, 'sign.rb'
  end

  after :each do
    Coverage.result unless Coverage.state == :idle
  end

  it "returns nil" do
    Coverage.start
    Coverage.suspend.should == nil
  end

  it "stops the coverage measurement" do
    Coverage.start
    Coverage.suspend
    Coverage.running?.should == false
  end

  it "raises a RuntimeError when the coverage measurement is not running" do
    -> {
      Coverage.suspend
    }.should.raise(RuntimeError, 'coverage measurement is not running')
  end

  it "raises a RuntimeError when the coverage measurement is already suspended" do
    Coverage.setup

    -> {
      Coverage.suspend
    }.should.raise(RuntimeError, 'coverage measurement is not running')
  end

  it "keeps the result so far" do
    Coverage.start
    load @file
    Coverage.suspend
    Coverage.peek_result.should == { @file => [1, 1, 0, nil, nil] }
  end

  it "stops counting lines" do
    Coverage.start(lines: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.suspend
    CoverageSpecs.sign(1)
    Coverage.result[@file][:lines].should == [1, 1, 1, nil, nil]
  end

  it "stops counting branches" do
    Coverage.start(branches: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.suspend
    CoverageSpecs.sign(-1)
    Coverage.result[@file][:branches].should == {
      [:if, 0, 3, 4, 3, 33] => {
        [:then, 1, 3, 12, 3, 21] => 0,
        [:else, 2, 3, 24, 3, 33] => 1
      }
    }
  end

  it "stops counting method calls" do
    Coverage.start(methods: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.suspend
    CoverageSpecs.sign(1)
    Coverage.result[@file][:methods].should == {
      [CoverageSpecs.singleton_class, :sign, 2, 2, 4, 5] => 1
    }
  end
end
