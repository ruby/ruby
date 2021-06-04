require 'date'
require_relative '../../spec_helper'

describe "Date#julian?" do

  it "marks a day before the calendar reform as Julian" do
    Date.civil(1007, 2, 27).should.julian?
    Date.civil(1907, 2, 27, Date.civil(1930, 1, 1).jd).julian?.should be_true
  end

  it "marks a day after the calendar reform as Julian" do
    Date.civil(2007, 2, 27).should_not.julian?
    Date.civil(1607, 2, 27, Date.civil(1582, 1, 1).jd).julian?.should be_false
  end

end
