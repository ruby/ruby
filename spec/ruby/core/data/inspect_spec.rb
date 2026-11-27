require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#inspect" do
  it "is an alias of Data#to_s" do
    DataSpecs::Measure.instance_method(:inspect).should == DataSpecs::Measure.instance_method(:to_s)
  end
end
