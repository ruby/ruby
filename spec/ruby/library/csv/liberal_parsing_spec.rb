require_relative '../../spec_helper'
require 'csv'

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
