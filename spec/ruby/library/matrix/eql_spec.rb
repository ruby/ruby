require_relative '../../spec_helper'
require_relative 'shared/equal_value'
require 'matrix'

describe "Matrix#eql?" do
  it_behaves_like :equal, :eql?

  it "returns false if some elements are == but not eql?" do
    Matrix[[1, 2],[3, 4]].eql?(Matrix[[1, 2],[3, 4.0]]).should be_false
  end
end
