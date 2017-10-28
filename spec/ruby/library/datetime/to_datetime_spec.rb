require File.expand_path('../../../spec_helper', __FILE__)
require 'date'

describe "DateTime#to_datetime" do
  it "returns itself" do
    dt = DateTime.new(2012, 12, 24, 12, 23, 00, '+05:00')
    dt.to_datetime.should == dt
  end
end
