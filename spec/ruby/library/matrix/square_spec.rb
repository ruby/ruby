require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#square?" do

  it "returns true when the Matrix is square" do
    Matrix[ [1,2], [2,4] ].square?.should == true
    Matrix[ [100,3,5], [9.5, 4.9, 8], [2,0,77] ].square?.should == true
  end

  it "returns true when the Matrix has only one element" do
    Matrix[ [9] ].square?.should == true
  end

  it "returns false when the Matrix is rectangular" do
    Matrix[ [1, 2] ].square?.should == false
  end

  it "returns false when the Matrix is rectangular" do
    Matrix[ [1], [2] ].square?.should == false
  end

  it "returns handles empty matrices" do
    Matrix[].square?.should == true
    Matrix[[]].square?.should == false
    Matrix.columns([[]]).square?.should == false
  end
end
