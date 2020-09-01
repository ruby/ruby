require_relative '../../spec_helper'

ruby_version_is ''...'2.8' do
  describe "Data" do
    it "is a subclass of Object" do
      suppress_warning do
        Data.superclass.should == Object
      end
    end

    it "is deprecated" do
      -> { Data }.should complain(/constant ::Data is deprecated/)
    end
  end
end
