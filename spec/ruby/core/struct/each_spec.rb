require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/accessor'
require_relative '../enumerable/shared/enumeratorized'

describe "Struct#each" do
  it "passes each value to the given block" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    i = -1
    car.each do |value|
      value.should == car[i += 1]
    end
  end

  it "returns self if passed a block" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.each {}.should == car
  end

  it "returns an Enumerator if not passed a block" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.each.should be_an_instance_of(Enumerator)
  end

  it_behaves_like :struct_accessor, :each
  it_behaves_like :enumeratorized_with_origin_size, :each, StructClasses::Car.new('Ford', 'Ranger')
end
