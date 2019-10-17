require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/equal_value'

describe "Struct#eql?" do
  it_behaves_like :struct_equal_value, :eql?

  it "returns false if any corresponding elements are not #eql?" do
    car = StructClasses::Car.new("Honda", "Accord", 1998)
    similar_car = StructClasses::Car.new("Honda", "Accord", 1998.0)
    car.should_not eql(similar_car)
  end
end
