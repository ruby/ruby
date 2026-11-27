require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#filter" do
  it "is an alias of Struct#select" do
    StructClasses::Car.instance_method(:filter).should == StructClasses::Car.instance_method(:select)
  end
end
