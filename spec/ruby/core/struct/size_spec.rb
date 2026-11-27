require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/accessor'

describe "Struct#size" do
  it "returns the number of attributes" do
    StructClasses::Car.new('Cadillac', 'DeVille').length.should == 3
    StructClasses::Car.new.length.should == 3
  end

  it_behaves_like :struct_accessor, :size
end
