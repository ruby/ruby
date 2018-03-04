require_relative '../spec_helper'

with_feature :readline do
  describe "Readline::HISTORY.to_s" do
    it "returns 'HISTORY'" do
      Readline::HISTORY.to_s.should == "HISTORY"
    end
  end
end
