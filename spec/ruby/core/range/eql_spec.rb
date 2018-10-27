require_relative '../../spec_helper'
require_relative 'shared/equal_value'

describe "Range#eql?" do
  it_behaves_like :range_eql, :eql?

  it "returns false if the endpoints are not eql?" do
    (0..1).should_not eql(0..1.0)
  end
end
