require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix#hash" do

    it "returns an Integer" do
      Matrix[ [1,2] ].hash.should be_an_instance_of(Integer)
    end

    it "returns the same value for the same matrix" do
      data = [ [40,5], [2,7] ]
      Matrix[ *data ].hash.should == Matrix[ *data ].hash
    end

  end
end
