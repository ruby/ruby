require_relative '../../spec_helper'
require 'date'

describe "DateTime#-" do
  it "is able to subtract sub-millisecond precision values" do
    date = DateTime.new(2017)
    ((date + 0.00001) - date).should == Rational(1, 100000)
  end
end
