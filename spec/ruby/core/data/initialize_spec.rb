require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#initialize" do
  it "accepts positional arguments" do
    data = DataSpecs::Measure.new(42, "km")

    data.amount.should == 42
    data.unit.should == "km"
  end

  it "accepts alternative positional arguments" do
    data = DataSpecs::Measure[42, "km"]

    data.amount.should == 42
    data.unit.should == "km"
  end

  it "accepts keyword arguments" do
    data = DataSpecs::Measure.new(amount: 42, unit: "km")

    data.amount.should == 42
    data.unit.should == "km"
  end

  it "accepts alternative keyword arguments" do
    data = DataSpecs::Measure[amount: 42, unit: "km"]

    data.amount.should == 42
    data.unit.should == "km"
  end

  it "accepts String keyword arguments" do
    data = DataSpecs::Measure.new("amount" => 42, "unit" => "km")

    data.amount.should == 42
    data.unit.should == "km"
  end

  it "raises ArgumentError if no arguments are given" do
    -> {
      DataSpecs::Measure.new
    }.should raise_error(ArgumentError) { |e|
      e.message.should.include?("missing keywords: :amount, :unit")
    }
  end

  it "raises ArgumentError if at least one argument is missing" do
    -> {
      DataSpecs::Measure.new(unit: "km")
    }.should raise_error(ArgumentError) { |e|
      e.message.should.include?("missing keyword: :amount")
    }
  end

  it "raises ArgumentError if unknown keyword is given" do
    -> {
      DataSpecs::Measure.new(amount: 42, unit: "km", system: "metric")
    }.should raise_error(ArgumentError) { |e|
      e.message.should.include?("unknown keyword: :system")
    }
  end

  it "supports super from a subclass" do
    ms = DataSpecs::MeasureSubclass.new(amount: 1, unit: "km")

    ms.amount.should == 1
    ms.unit.should == "km"
  end

  it "supports Data with no fields" do
    -> { DataSpecs::Empty.new }.should_not raise_error
  end
end
