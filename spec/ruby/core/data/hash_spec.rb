require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#hash" do
  it "returns the same integer for objects with the same content" do
    a = DataSpecs::Measure.new(42, "km")
    b = DataSpecs::Measure.new(42, "km")
    a.hash.should == b.hash
    a.hash.should be_an_instance_of(Integer)
  end

  it "returns different hashes for objects with different values" do
    a = DataSpecs::Measure.new(42, "km")
    b = DataSpecs::Measure.new(42, "ml")
    a.hash.should_not == b.hash

    a = DataSpecs::Measure.new(42, "km")
    b = DataSpecs::Measure.new(13, "km")
    a.hash.should_not == b.hash
  end

  it "returns different hashes for different classes" do
    Data.define(:x).new(1).hash.should != Data.define(:x).new(1).hash
  end
end
