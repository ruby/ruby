require_relative '../../spec_helper'

describe "Hash#has_key?" do
  it "is an alias of Hash#include?" do
    Hash.instance_method(:has_key?).should == Hash.instance_method(:include?)
  end
end
