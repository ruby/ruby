require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/inspect'

describe "Struct#to_s" do
  it "is a synonym for inspect" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.inspect.should == car.to_s
  end

  it_behaves_like :struct_inspect, :to_s
end
