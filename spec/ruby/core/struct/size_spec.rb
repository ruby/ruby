require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/accessor'

describe "Struct#size" do
  it "is a synonym for length" do
    StructClasses::Car.new.size.should == StructClasses::Car.new.length
  end

  it_behaves_like :struct_accessor, :size
end
