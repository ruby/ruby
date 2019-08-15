require_relative '../spec_helper'

with_feature :readline do
  describe "Readline::HISTORY.empty?" do
    it "returns true when the history is empty" do
      Readline::HISTORY.should be_empty
      Readline::HISTORY.push("test")
      Readline::HISTORY.should_not be_empty
      Readline::HISTORY.pop
      Readline::HISTORY.should be_empty
    end
  end
end
