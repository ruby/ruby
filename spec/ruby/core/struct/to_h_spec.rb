require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Struct#to_h" do
  it "returns a Hash with members as keys" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.to_h.should == {make: "Ford", model: "Ranger", year: nil}
  end

  it "returns a Hash that is independent from the struct" do
    car = StructClasses::Car.new('Ford', 'Ranger')
    car.to_h[:make] = 'Suzuki'
    car.make.should == 'Ford'
  end

  ruby_version_is "2.6" do
    it "converts [key, value] pairs returned by the block to a hash" do
      car = StructClasses::Car.new('Ford', 'Ranger')
      h = car.to_h {|k, v| [k.to_s, "#{v}".downcase]}
      h.should == {"make" => "ford", "model" => "ranger", "year" => ""}
    end
  end
end
