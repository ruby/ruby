require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#wednesday?" do
  it "should be wednesday" do
    Date.new(2000, 1, 5).wednesday?.should be_true
  end
end
