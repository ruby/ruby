require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#eql?" do
  it "returns true if the other is the same object" do
    a = DataSpecs::Measure.new(42, "km")
    a.should.eql?(a)
  end

  it "returns true if the other has all the same fields" do
    a = DataSpecs::Measure.new(42, "km")
    b = DataSpecs::Measure.new(42, "km")
    a.should.eql?(b)
  end

  it "returns false if the other is a different object or has different fields" do
    a = DataSpecs::Measure.new(42, "km")
    b = DataSpecs::Measure.new(42, "mi")
    a.should_not.eql?(b)
  end

  it "returns false if other is of a different class" do
    a = DataSpecs::Measure.new(42, "km")
    klass = Data.define(*DataSpecs::Measure.members)
    b = klass.new(42, "km")
    a.should_not.eql?(b)
  end

  it "returns false if any corresponding elements are not equal with #eql?" do
    a = DataSpecs::Measure.new(42, "km")
    b = DataSpecs::Measure.new(42.0, "mi")
    a.should_not.eql?(b)
  end

  context "recursive structure" do
    it "returns true the other is the same object" do
      a = DataSpecs::Measure.allocate
      a.send(:initialize, amount: 42, unit: a)

      a.should.eql?(a)
    end

    it "returns true if the other has all the same fields" do
      a = DataSpecs::Measure.allocate
      a.send(:initialize, amount: 42, unit: a)

      b = DataSpecs::Measure.allocate
      b.send(:initialize, amount: 42, unit: b)

      a.should.eql?(b)
    end

    it "returns false if any corresponding elements are not equal with #eql?" do
      a = DataSpecs::Measure.allocate
      a.send(:initialize, amount: a, unit: "km")

      b = DataSpecs::Measure.allocate
      b.send(:initialize, amount: b, unit: "mi")

      a.should_not.eql?(b)
    end
  end
end
