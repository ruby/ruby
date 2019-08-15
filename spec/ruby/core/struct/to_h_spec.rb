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
    context "with block" do
      it "converts [key, value] pairs returned by the block to a hash" do
        car = StructClasses::Car.new('Ford', 'Ranger')

        h = car.to_h { |k, v| [k.to_s, "#{v}".downcase] }
        h.should == { "make" => "ford", "model" => "ranger", "year" => "" }
      end

      it "raises ArgumentError if block returns longer or shorter array" do
        -> do
          StructClasses::Car.new.to_h { |k, v| [k.to_s, "#{v}".downcase, 1] }
        end.should raise_error(ArgumentError, /element has wrong array length/)

        -> do
          StructClasses::Car.new.to_h { |k, v| [k] }
        end.should raise_error(ArgumentError, /element has wrong array length/)
      end

      it "raises TypeError if block returns something other than Array" do
        -> do
          StructClasses::Car.new.to_h { |k, v| "not-array" }
        end.should raise_error(TypeError, /wrong element type String/)
      end

      it "coerces returned pair to Array with #to_ary" do
        x = mock('x')
        x.stub!(:to_ary).and_return([:b, 'b'])

        StructClasses::Car.new.to_h { |k| x }.should == { :b => 'b' }
      end

      it "does not coerce returned pair to Array with #to_a" do
        x = mock('x')
        x.stub!(:to_a).and_return([:b, 'b'])

        -> do
          StructClasses::Car.new.to_h { |k| x }
        end.should raise_error(TypeError, /wrong element type MockObject/)
      end
    end
  end
end
