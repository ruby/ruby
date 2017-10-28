require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#friday?" do
  it "should be friday" do
    Date.new(2000, 1, 7).friday?.should be_true
  end

  it "should not be friday" do
    Date.new(2000, 1, 8).friday?.should be_false
  end
end
