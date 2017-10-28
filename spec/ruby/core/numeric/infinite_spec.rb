require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is "2.4" do
  describe "Numeric#infinite?" do
    it "returns nil by default" do
      o = mock_numeric("infinite")
      o.infinite?.should == nil
    end
  end
end
