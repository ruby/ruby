require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.2" do
  describe "Data#members" do
    it "returns an array of attribute names" do
      measure = DataSpecs::Measure.new(amount: 42, unit: 'km')
      measure.members.should == [:amount, :unit]
    end
  end

  describe "DataClass#members" do
    it "returns an array of attribute names" do
      DataSpecs::Measure.members.should == [:amount, :unit]
    end

    context "class inheriting Data" do
      it "isn't available in a subclass" do
        DataSpecs::DataSubclass.should_not.respond_to?(:members)
      end
    end
  end
end
