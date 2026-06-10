require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#inspect" do
  it "is an alias of Struct#to_s" do
    StructClasses::Car.instance_method(:inspect).should == StructClasses::Car.instance_method(:to_s)
  end
end
