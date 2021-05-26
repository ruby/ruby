require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix#row_vectors" do

    before :each do
      @vectors = Matrix[ [1,2], [3,4] ].row_vectors
    end

    it "returns an Array" do
      Matrix[ [1,2], [3,4] ].row_vectors.should be_an_instance_of(Array)
    end

    it "returns an Array of Vectors" do
      @vectors.all? {|v| v.should be_an_instance_of(Vector)}
    end

    it "returns each row as a Vector" do
      @vectors.should == [Vector[1,2], Vector[3,4]]
    end

    it "returns an empty Array for empty matrices" do
      Matrix[].row_vectors.should == []
      Matrix[ [] ].row_vectors.should == [ Vector[] ]
    end
  end
end
