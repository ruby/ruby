require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix#coerce" do
    it "allows the division of integer by a Matrix " do
      (1/Matrix[[0,1],[-1,0]]).should == Matrix[[0,-1],[1,0]]
    end
  end
end
