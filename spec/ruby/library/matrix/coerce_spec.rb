require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#coerce" do
  it "allows the division of fixnum by a Matrix " do
    (1/Matrix[[0,1],[-1,0]]).should == Matrix[[0,-1],[1,0]]
  end
end
