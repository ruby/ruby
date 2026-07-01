require_relative '../../spec_helper'

describe "Hash#member?" do
  it "is an alias of Hash#include?" do
    Hash.instance_method(:member?).should == Hash.instance_method(:include?)
  end
end
