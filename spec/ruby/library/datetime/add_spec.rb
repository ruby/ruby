require_relative '../../spec_helper'
require 'date'

describe "DateTime#+" do
  it "is able to add sub-millisecond precision values" do
    datetime = DateTime.new(2017)
    (datetime + 0.00001001).to_time.usec.should == 864864
  end
end
