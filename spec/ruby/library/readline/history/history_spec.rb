require_relative '../spec_helper'

with_feature :readline do
  describe "Readline::HISTORY" do
    it "is extended with the Enumerable module" do
      Readline::HISTORY.should.is_a?(Enumerable)
    end
  end
end
