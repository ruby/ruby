require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#to_s" do
  it "is an alias of Data#inspect" do
    a = DataSpecs::Measure.new(42, "km")
    a.method(:to_s).should == a.method(:inspect)
  end
end
