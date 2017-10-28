require File.expand_path('../../../spec_helper', __FILE__)

ruby_version_is "2.4" do
  describe "Numeric#finite?" do
    it "returns true by default" do
      o = mock_numeric("finite")
      o.finite?.should be_true
    end
  end
end
