require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#values" do
  it "is an alias of Struct#to_a" do
    StructClasses::Car.instance_method(:values).should == StructClasses::Car.instance_method(:to_a)
  end
end
