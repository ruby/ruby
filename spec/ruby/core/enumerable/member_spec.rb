require_relative '../../spec_helper'

describe "Enumerable#member?" do
  it "is an alias of Enumerable#include?" do
    Enumerable.instance_method(:member?).should == Enumerable.instance_method(:include?)
  end
end
