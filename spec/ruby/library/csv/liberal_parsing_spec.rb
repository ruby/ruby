require File.expand_path('../../../spec_helper', __FILE__)
require 'csv'

ruby_version_is '2.4' do
  describe "CSV#liberal_parsing?" do
    it "returns true if illegal input is handled" do
      csv = CSV.new("", liberal_parsing: true)
      csv.liberal_parsing?.should == true
    end

    it "returns false if illegal input is not handled" do
      csv = CSV.new("", liberal_parsing: false)
      csv.liberal_parsing?.should == false
    end

    it "returns false by default" do
      csv = CSV.new("")
      csv.liberal_parsing?.should == false
    end
  end
end
