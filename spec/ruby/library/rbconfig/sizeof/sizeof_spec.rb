require_relative '../../../spec_helper'
require 'rbconfig/sizeof'

describe "RbConfig::SIZEOF" do
  it "is a Hash" do
    RbConfig::SIZEOF.should be_kind_of(Hash)
  end

  it "has string keys and integer values" do
    RbConfig::SIZEOF.each do |key, value|
      key.should be_kind_of String
      value.should be_kind_of Integer
    end
  end

  it "contains the sizeof(void*)" do
    (RbConfig::SIZEOF["void*"] * 8).should == PlatformGuard::POINTER_SIZE
  end

  it "contains the sizeof(float) and sizeof(double)" do
    RbConfig::SIZEOF["float"].should == 4
    RbConfig::SIZEOF["double"].should == 8
  end

  it "contains the size of short, int and long" do
    RbConfig::SIZEOF["short"].should > 0
    RbConfig::SIZEOF["int"].should > 0
    RbConfig::SIZEOF["long"].should > 0
  end
end
