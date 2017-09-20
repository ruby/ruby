require File.expand_path('../../../spec_helper', __FILE__)
require File.expand_path('../fixtures/classes', __FILE__)
require File.expand_path('../shared/inspect', __FILE__)

describe "Struct#inspect" do
  it "returns a string representation of some kind" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.inspect.should == '#<struct StructClasses::Car make="Ford", model="Ranger", year=nil>'

    Whiskey = Struct.new(:name, :ounces)
    Whiskey.new('Jack', 100).inspect.should == '#<struct Whiskey name="Jack", ounces=100>'
  end

  it_behaves_like(:struct_inspect, :inspect)
end
