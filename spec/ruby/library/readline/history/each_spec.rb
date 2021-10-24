require_relative '../spec_helper'

with_feature :readline do
  describe "Readline::HISTORY.each" do
    before :each do
      Readline::HISTORY.push("1", "2", "3")
    end

    after :each do
      Readline::HISTORY.pop
      Readline::HISTORY.pop
      Readline::HISTORY.pop
    end

    it "yields each item in the history" do
      result = []
      Readline::HISTORY.each do |x|
        result << x
      end
      result.should == ["1", "2", "3"]
    end

    ruby_version_is ''...'2.7' do
      it "yields tainted Objects" do
        Readline::HISTORY.each do |x|
          x.tainted?.should be_true
        end
      end
    end
  end
end
