require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#with" do
  it "returns self if given no arguments" do
    data = DataSpecs::Measure.new(amount: 42, unit: "km")
    data = data.with.should.equal?(data)
  end

  it "accepts keyword arguments" do
    data = DataSpecs::Measure.new(amount: 42, unit: "km")
    data = data.with(amount: 4, unit: "m")

    data.amount.should == 4
    data.unit.should == "m"
  end

  it "accepts String keyword arguments" do
    data = DataSpecs::Measure.new(amount: 42, unit: "km")
    data = data.with("amount" => 4, "unit" => "m")

    data.amount.should == 4
    data.unit.should == "m"
  end

  it "raises ArgumentError if no keyword arguments are given" do
    data = DataSpecs::Measure.new(amount: 42, unit: "km")

    -> {
      data.with(4, "m")
    }.should raise_error(ArgumentError, "wrong number of arguments (given 2, expected 0)")
  end

  it "does not depend on the Data.new method" do
    subclass = Class.new(DataSpecs::Measure)
    data = subclass.new(amount: 42, unit: "km")

    def subclass.new(*)
      raise "Data.new is called"
    end

    data_copy = data.with(unit: "m")
    data_copy.amount.should == 42
    data_copy.unit.should == "m"
  end

  ruby_version_is "3.3" do
    it "calls #initialize" do
      data = DataSpecs::DataWithOverriddenInitialize.new(42, "m")
      ScratchPad.clear

      data.with(amount: 0)

      ScratchPad.recorded.should == [:initialize, [], {amount: 0, unit: "m"}]
    end
  end
end
