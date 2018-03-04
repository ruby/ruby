require_relative '../../spec_helper'

ruby_version_is "2.4" do
  describe "Numeric#infinite?" do
    it "returns nil by default" do
      o = mock_numeric("infinite")
      o.infinite?.should == nil
    end
  end
end
