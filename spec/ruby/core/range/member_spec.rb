require_relative '../../spec_helper'

describe "Range#member?" do
  it "is an alias of Range#include?" do
    Range.instance_method(:member?).should == Range.instance_method(:include?)
  end
end
