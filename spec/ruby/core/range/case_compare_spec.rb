require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/cover'

describe "Range#===" do
  it "returns the result of calling #cover? on self" do
    range = RangeSpecs::WithoutSucc.new(0)..RangeSpecs::WithoutSucc.new(10)
    (range === RangeSpecs::WithoutSucc.new(2)).should == true
  end

  it_behaves_like :range_cover_and_include, :===
  it_behaves_like :range_cover, :===
end
