require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.2" do
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
  end
end
