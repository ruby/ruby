require_relative '../../spec_helper'
require 'date'

describe "Date#asctime" do
  it "returns a canonical string representation of date" do
    d = Date.today
    d.asctime.should == d.strftime("%a %b %e %H:%M:%S %Y")
  end
end
