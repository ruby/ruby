require_relative '../../spec_helper'
require_relative '../../shared/enumerable/minmax'

describe "Array#minmax" do
  before :each do
    @enum = [6, 4, 5, 10, 8]
    @empty_enum = []
    @incomparable_enum = [BasicObject.new, BasicObject.new]
    @incompatible_enum = [11, "22"]
    @strs = ["333", "2", "60", "55555", "1010", "111"]
  end

  it_behaves_like :enumerable_minmax, :minmax
end
