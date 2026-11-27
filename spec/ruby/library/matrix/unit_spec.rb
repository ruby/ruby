require_relative '../../spec_helper'
require 'matrix'

describe "Matrix.unit" do
  it "is an alias of Matrix.identity" do
    Matrix.method(:unit).should == Matrix.method(:identity)
  end
end
