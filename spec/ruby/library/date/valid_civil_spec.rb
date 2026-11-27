require_relative '../../spec_helper'
require 'date'

describe "Date.valid_civil?" do
  it "is an alias of Date.valid_date?" do
    Date.method(:valid_civil?).should == Date.method(:valid_date?)
  end
end
