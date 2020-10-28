require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#instance_variable_get" do
  it "returns nil for attributes" do
    car = StructClasses::Car.new("Hugo", "Foo", "1972")
    car.instance_variable_get(:@make).should be_nil
  end

  it "returns a user value for variables with the same name as attributes" do
    car = StructClasses::Car.new("Hugo", "Foo", "1972")
    car.instance_variable_set :@make, "explicit"
    car.instance_variable_get(:@make).should == "explicit"
    car.make.should == "Hugo"
  end
end
