require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#initialize" do
  context "with no members" do
    ruby_bug "#21819", ""..."4.0.1" do
      it "is frozen" do
        data = Data.define

        data.new.should.frozen?
      end
    end
  end

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

  it "accepts the last entry when a keyword is given as both String and Symbol" do
    data = DataSpecs::Single.new("value" => -1, value: 42)

    data.value.should == 42
  end

  it "accepts positional arguments with empty keyword arguments" do
    data = DataSpecs::Single.new(42, **{})

    data.value.should == 42

    data = DataSpecs::Measure.new(42, "km", **{})

    data.amount.should == 42
    data.unit.should == "km"
  end

  it "raises ArgumentError if no arguments are given" do
    -> {
      DataSpecs::Measure.new
    }.should.raise(ArgumentError) { |e|
      e.message.should.include?("missing keywords: :amount, :unit")
    }
  end

  it "raises ArgumentError if at least one argument is missing" do
    -> {
      DataSpecs::Measure.new(unit: "km")
    }.should.raise(ArgumentError) { |e|
      e.message.should.include?("missing keyword: :amount")
    }
  end

  ruby_version_is "4.0" do # https://bugs.ruby-lang.org/issues/21844
    it "raises ArgumentError if at least one argument is missing and other is provided as both String and Symbol" do
      -> {
        DataSpecs::Measure.new(unit: "km", "unit" => "km")
      }.should.raise(ArgumentError) { |e|
        e.message.should.include?("missing keyword: :amount")
      }
    end
  end

  it "raises ArgumentError if unknown keyword is given" do
    -> {
      DataSpecs::Measure.new(amount: 42, unit: "km", system: "metric")
    }.should.raise(ArgumentError) { |e|
      e.message.should.include?("unknown keyword: :system")
    }
  end

  ruby_version_is "4.0" do # https://bugs.ruby-lang.org/issues/21844
    it "raises ArgumentError if unknown keyword is given which is convertable to String" do
      key = mock("to_str")
      key.should_receive(:to_str).and_return("system")

      -> {
        DataSpecs::Measure.new(amount: 42, unit: "km", key => "metric")
      }.should.raise(ArgumentError) { |e|
        e.message.should.include?('unknown keyword: "system"')
      }
    end

    it "raises TypeError when the keyword is not convertable to String" do
      -> {
        DataSpecs::Measure.new(1 => 2)
      }.should.raise(TypeError) { |e|
        e.message.should == "1 is not a symbol nor a string"
      }
    end

    it "raises TypeError if the conversion with #to_str does not return a String" do
      klass = Data.define(:x, :y)

      key = mock("to_str")
      key.should_receive(:to_str).and_return(0)

      -> {
        klass.new(key => 2)
      }.should raise_consistent_error(TypeError, /can't convert MockObject into String/)
    end
  end

  it "supports super from a subclass" do
    ms = DataSpecs::MeasureSubclass.new(amount: 1, unit: "km")

    ms.amount.should == 1
    ms.unit.should == "km"
  end

  it "supports Data with no fields" do
    -> { DataSpecs::Empty.new }.should_not.raise
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

    it "accepts positional arguments with empty keyword arguments" do
      data = DataSpecs::SingleWithOverriddenName.new(42, **{})

      data.value.should == 42

      data = DataSpecs::MeasureWithOverriddenName.new(42, "km", **{})

      data.amount.should == 42
      data.unit.should == "km"
    end

    # See https://github.com/ruby/psych/pull/765
    it "can be deserialized by calling Data.instance_method(:initialize)" do
      d1 = DataSpecs::Area.new(width: 2, height: 3)
      d1.area.should == 6

      d2 = DataSpecs::Area.allocate
      Data.instance_method(:initialize).bind_call(d2, **d1.to_h)
      d2.should == d1
    end
  end
end
