require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct[]" do
  it "is a synonym for new" do
    StructClasses::Ruby['2.0', 'i686'].should be_kind_of(StructClasses::Ruby)
  end
end

describe "Struct#[]" do
  it "returns the attribute referenced" do
    car = StructClasses::Car.new('Ford', 'Ranger', 1983)
    car['make'].should == 'Ford'
    car['model'].should == 'Ranger'
    car['year'].should == 1983
    car[:make].should == 'Ford'
    car[:model].should == 'Ranger'
    car[:year].should == 1983
    car[0].should == 'Ford'
    car[1].should == 'Ranger'
    car[2].should == 1983
    car[-3].should == 'Ford'
    car[-2].should == 'Ranger'
    car[-1].should == 1983
  end

  it "fails when it does not know about the requested attribute" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    -> { car[3]        }.should raise_error(IndexError)
    -> { car[-4]       }.should raise_error(IndexError)
    -> { car[:body]    }.should raise_error(NameError)
    -> { car['wheels'] }.should raise_error(NameError)
  end

  it "fails if passed too many arguments" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    -> { car[:make, :model] }.should raise_error(ArgumentError)
  end

  it "fails if not passed a string, symbol, or integer" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    -> { car[Object.new] }.should raise_error(TypeError)
  end

  it "returns attribute names that contain hyphens" do
    klass = Struct.new(:'current-state')
    tuple = klass.new(0)
    tuple['current-state'].should == 0
    tuple[:'current-state'].should == 0
    tuple[0].should == 0
  end
end
