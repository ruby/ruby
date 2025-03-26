require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.2" do
  describe "Data#deconstruct" do
    it "returns an array of attribute values" do
      DataSpecs::Measure.new(42, "km").deconstruct.should == [42, "km"]
    end
  end
end
