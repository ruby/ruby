require_relative '../../spec_helper'
require 'date'

describe "Date.rfc3339" do
  it "needs to be reviewed for spec completeness"
end

describe "Date._rfc3339" do
  it "returns an empty hash if the argument is a invalid Date" do
    h = Date._rfc3339('invalid')
    h.should == {}
  end
end
