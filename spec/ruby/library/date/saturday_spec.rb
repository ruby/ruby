require_relative '../../spec_helper'
require 'date'

describe "Date#saturday?" do
  it "should be saturday" do
    Date.new(2000, 1, 1).saturday?.should be_true
  end
end
