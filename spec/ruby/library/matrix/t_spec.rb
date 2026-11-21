require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#t" do
  it "is an alias of Matrix#transpose" do
    Matrix.instance_method(:t).should == Matrix.instance_method(:transpose)
  end
end
