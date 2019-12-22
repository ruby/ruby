require_relative '../spec_helper'

with_feature :readline do
  describe "Readline::HISTORY.[]" do
    before :each do
      Readline::HISTORY.push("1", "2", "3")
    end

    after :each do
      Readline::HISTORY.pop
      Readline::HISTORY.pop
      Readline::HISTORY.pop
    end

    ruby_version_is ''...'2.7' do
      it "returns tainted objects" do
        Readline::HISTORY[0].tainted?.should be_true
        Readline::HISTORY[1].tainted?.should be_true
      end
    end

    it "returns the history item at the passed index" do
      Readline::HISTORY[0].should == "1"
      Readline::HISTORY[1].should == "2"
      Readline::HISTORY[2].should == "3"

      Readline::HISTORY[-1].should == "3"
      Readline::HISTORY[-2].should == "2"
      Readline::HISTORY[-3].should == "1"
    end

    it "raises an IndexError when there is no item at the passed index" do
      -> { Readline::HISTORY[-10] }.should raise_error(IndexError)
      -> { Readline::HISTORY[-9] }.should raise_error(IndexError)
      -> { Readline::HISTORY[-8] }.should raise_error(IndexError)

      -> { Readline::HISTORY[8] }.should raise_error(IndexError)
      -> { Readline::HISTORY[9] }.should raise_error(IndexError)
      -> { Readline::HISTORY[10] }.should raise_error(IndexError)
    end
  end
end
