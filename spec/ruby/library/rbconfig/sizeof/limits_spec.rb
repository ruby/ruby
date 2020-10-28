require_relative '../../../spec_helper'
require 'rbconfig/sizeof'

describe "RbConfig::LIMITS" do
  it "is a Hash" do
    RbConfig::LIMITS.should be_kind_of(Hash)
  end

  it "has string keys and numeric values" do
    RbConfig::LIMITS.each do |key, value|
      key.should be_kind_of String
      value.should be_kind_of Numeric
    end
  end

  it "contains FIXNUM_MIN and FIXNUM_MAX" do
    RbConfig::LIMITS["FIXNUM_MIN"].should < 0
    RbConfig::LIMITS["FIXNUM_MAX"].should > 0
  end

  it "contains CHAR_MIN and CHAR_MAX" do
    RbConfig::LIMITS["CHAR_MIN"].should <= 0
    RbConfig::LIMITS["CHAR_MAX"].should > 0
  end

  it "contains SHRT_MIN and SHRT_MAX" do
    RbConfig::LIMITS["SHRT_MIN"].should == -32768
    RbConfig::LIMITS["SHRT_MAX"].should == 32767
  end

  it "contains INT_MIN and INT_MAX" do
    RbConfig::LIMITS["INT_MIN"].should < 0
    RbConfig::LIMITS["INT_MAX"].should > 0
  end

  it "contains LONG_MIN and LONG_MAX" do
    RbConfig::LIMITS["LONG_MIN"].should < 0
    RbConfig::LIMITS["LONG_MAX"].should > 0
  end
end
