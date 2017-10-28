require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#thursday?" do
  it "should be thursday" do
    Date.new(2000, 1, 6).thursday?.should be_true
  end
end
