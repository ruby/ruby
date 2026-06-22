require_relative '../../spec_helper'

describe "Set#member?" do
  it "is an alias of Set#include?" do
    Set.instance_method(:member?).should == Set.instance_method(:include?)
  end
end
