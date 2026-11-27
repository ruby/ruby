require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#length" do
  it "is an alias of Struct#size" do
    StructClasses::Car.instance_method(:length).should == StructClasses::Car.instance_method(:size)
  end
end
