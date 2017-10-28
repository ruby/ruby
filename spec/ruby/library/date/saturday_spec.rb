require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#saturday?" do
  it "should be saturday" do
    Date.new(2000, 1, 1).saturday?.should be_true
  end
end
