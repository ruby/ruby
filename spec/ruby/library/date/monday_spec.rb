require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#monday?" do
  it "should be monday" do
    Date.new(2000, 1, 3).monday?.should be_true
  end
end
