require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#inv" do
  it "is an alias of Matrix#inverse" do
    Matrix.instance_method(:inv).should == Matrix.instance_method(:inverse)
  end
end
