require_relative '../../spec_helper'
require 'date'

describe "Date#sunday?" do
  it "should be sunday" do
    Date.new(2000, 1, 2).sunday?.should == true
  end
end
