require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#det" do
  it "is an alias of Matrix#determinant" do
    Matrix.instance_method(:det).should == Matrix.instance_method(:determinant)
  end
end
