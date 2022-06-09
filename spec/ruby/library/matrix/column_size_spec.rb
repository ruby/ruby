require_relative '../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix#column_size" do
    it "returns the number of columns" do
      Matrix[ [1,2], [3,4] ].column_size.should == 2
    end

    it "returns 0 for empty matrices" do
      Matrix[ [], [] ].column_size.should == 0
      Matrix[ ].column_size.should == 0
    end
  end
end
