require_relative '../../spec_helper'
require_relative 'shared/equal_value'

describe "Range#==" do
  it_behaves_like :range_eql, :==

  it "returns true if the endpoints are ==" do
    (0..1).should == (0..1.0)
  end
end
