require_relative '../../spec_helper'

ruby_version_is '2.7.2' do
  describe "Warning.[]" do
    it "returns default values for categories :deprecated and :experimental" do
      ruby_exe('p Warning[:deprecated]').chomp.should == "false"
      ruby_exe('p Warning[:experimental]').chomp.should == "true"
    end

    it "raises for unknown category" do
      -> { Warning[:noop] }.should raise_error(ArgumentError, /unknown category: noop/)
    end
  end
end
