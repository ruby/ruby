require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#[]=" do
  it "assigns the passed value" do
    car = StructClasses::Car.new('Ford', 'Ranger')

    car[:model] = 'Escape'
    car[:model].should == 'Escape'

    car['model'] = 'Fusion'
    car[:model].should == 'Fusion'

    car[1] = 'Excursion'
    car[:model].should == 'Excursion'

    car[-1] = '2000-2005'
    car[:year].should == '2000-2005'
  end

  it "fails when trying to assign attributes which don't exist" do
    car = StructClasses::Car.new('Ford', 'Ranger')

    -> { car[:something] = true }.should raise_error(NameError)
    -> { car[3] = true          }.should raise_error(IndexError)
    -> { car[-4] = true         }.should raise_error(IndexError)
    -> { car[Object.new] = true }.should raise_error(TypeError)
  end

  it "raises a FrozenError on a frozen struct" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.freeze

    -> { car[:model] = 'Escape' }.should raise_error(FrozenError)
  end
end
