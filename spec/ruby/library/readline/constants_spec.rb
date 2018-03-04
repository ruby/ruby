require_relative 'spec_helper'

with_feature :readline do
  # Note: additional specs for HISTORY are in 'history' subdir.
  describe "Readline::HISTORY" do
    it "is defined" do
      Readline.const_defined?(:HISTORY).should == true
    end
  end

  describe "Readline::VERSION" do
    it "is defined and is a non-empty String" do
      Readline.const_defined?(:VERSION).should == true
      Readline::VERSION.should be_kind_of(String)
      Readline::VERSION.should_not be_empty
    end
  end
end
