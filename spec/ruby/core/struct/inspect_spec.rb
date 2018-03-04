require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/inspect'

describe "Struct#inspect" do
  it "returns a string representation of some kind" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.inspect.should == '#<struct StructClasses::Car make="Ford", model="Ranger", year=nil>'

    Whiskey = Struct.new(:name, :ounces)
    Whiskey.new('Jack', 100).inspect.should == '#<struct Whiskey name="Jack", ounces=100>'
  end

  it_behaves_like :struct_inspect, :inspect
end
