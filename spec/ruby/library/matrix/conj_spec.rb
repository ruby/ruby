require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#conj" do
  it "is an alias of Matrix#conjugate" do
    Matrix.instance_method(:conj).should == Matrix.instance_method(:conjugate)
  end
end
