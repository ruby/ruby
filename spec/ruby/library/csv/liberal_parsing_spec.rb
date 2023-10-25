require_relative '../../spec_helper'
require 'csv'

describe "CSV#liberal_parsing?" do
  it "returns true if illegal input is handled" do
    csv = CSV.new("", liberal_parsing: true)
    csv.should.liberal_parsing?
  end

  it "returns false if illegal input is not handled" do
    csv = CSV.new("", liberal_parsing: false)
    csv.should_not.liberal_parsing?
  end

  it "returns false by default" do
    csv = CSV.new("")
    csv.should_not.liberal_parsing?
  end
end
