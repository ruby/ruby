require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "Date#sunday?" do
  it "should be sunday" do
    Date.new(2000, 1, 2).sunday?.should be_true
  end
end
