require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative '../../shared/enumerable/minmax'

describe "Enumerable#minmax" do
  before :each do
    @enum = EnumerableSpecs::Numerous.new(6, 4, 5, 10, 8)
    @empty_enum = EnumerableSpecs::Empty.new
    @incomparable_enum = EnumerableSpecs::Numerous.new(BasicObject.new, BasicObject.new)
    @incompatible_enum = EnumerableSpecs::Numerous.new(11,"22")
    @strs = EnumerableSpecs::Numerous.new("333", "2", "60", "55555", "1010", "111")
  end

  it_behaves_like :enumerable_minmax, :minmax

  it "gathers whole arrays as elements when each yields multiple" do
    multi = EnumerableSpecs::YieldsMulti.new
    multi.minmax.should == [[1, 2], [6, 7, 8, 9]]
  end
end
