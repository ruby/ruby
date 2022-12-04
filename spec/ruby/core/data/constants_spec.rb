require_relative '../../spec_helper'

ruby_version_is ''...'3.0' do
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

ruby_version_is '3.0'...'3.2' do
  describe "Data" do
    it "does not exist anymore" do
      Object.should_not have_constant(:Data)
    end
  end
end

ruby_version_is '3.2' do
  describe "Data" do
    it "is a new constant" do
      Data.superclass.should == Object
    end

    it "is not deprecated" do
      -> { Data }.should_not complain
    end
  end
end
