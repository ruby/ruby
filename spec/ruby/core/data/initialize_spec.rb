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

  it "can be overridden" do
    ScratchPad.record []

    measure_class = Data.define(:amount, :unit) do
      def initialize(*, **)
        super
        ScratchPad << :initialize
      end
    end

    measure_class.new(42, "m")
    ScratchPad.recorded.should == [:initialize]
  end

  context "when it is overridden" do
    it "is called with keyword arguments when given positional arguments" do
      ScratchPad.clear
      DataSpecs::DataWithOverriddenInitialize.new(42, "m")
      ScratchPad.recorded.should == [:initialize, [], {amount: 42, unit: "m"}]
    end

    it "is called with keyword arguments when given keyword arguments" do
      ScratchPad.clear
      DataSpecs::DataWithOverriddenInitialize.new(amount: 42, unit: "m")
      ScratchPad.recorded.should == [:initialize, [], {amount: 42, unit: "m"}]
    end

    it "is called with keyword arguments when given alternative positional arguments" do
      ScratchPad.clear
      DataSpecs::DataWithOverriddenInitialize[42, "m"]
      ScratchPad.recorded.should == [:initialize, [], {amount: 42, unit: "m"}]
    end

    it "is called with keyword arguments when given alternative keyword arguments" do
      ScratchPad.clear
      DataSpecs::DataWithOverriddenInitialize[amount: 42, unit: "m"]
      ScratchPad.recorded.should == [:initialize, [], {amount: 42, unit: "m"}]
    end
  end
end
