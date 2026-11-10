require_relative '../../spec_helper'
require 'coverage'

describe "Coverage.setup" do
  before :all do
    @file = fixture __FILE__, 'sign.rb'
  end

  after :each do
    Coverage.result unless Coverage.state == :idle
  end

  it "returns nil" do
    Coverage.setup.should == nil
  end

  it "does not start the coverage measurement" do
    Coverage.setup
    Coverage.running?.should == false
  end

  it "raises a RuntimeError when the coverage measurement is already set up" do
    Coverage.setup

    -> {
      Coverage.setup
    }.should.raise(RuntimeError, 'coverage measurement is already setup')
  end

  it "accepts :all optional argument" do
    Coverage.setup(:all)
    load @file
    Coverage.result[@file].keys.should == [:lines, :branches, :methods]
  end

  it "does not count lines until the coverage measurement is resumed" do
    Coverage.setup(lines: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.result[@file][:lines].should == [0, 0, 0, nil, nil]
  end

  it "does not count branches until the coverage measurement is resumed" do
    Coverage.setup(branches: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.result[@file][:branches].should == {
      [:if, 0, 3, 4, 3, 33] => {
        [:then, 1, 3, 12, 3, 21] => 0,
        [:else, 2, 3, 24, 3, 33] => 0
      }
    }
  end

  it "does not count method calls until the coverage measurement is resumed" do
    Coverage.setup(methods: true)
    load @file
    CoverageSpecs.sign(1)
    Coverage.result[@file][:methods].should == {
      [CoverageSpecs.singleton_class, :sign, 2, 2, 4, 5] => 0
    }
  end
end
