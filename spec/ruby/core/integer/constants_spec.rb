require_relative '../../spec_helper'

describe "Fixnum" do
  it "is no longer defined" do
    Object.should_not.const_defined?(:Fixnum)
  end
end

describe "Bignum" do
  it "is no longer defined" do
    Object.should_not.const_defined?(:Bignum)
  end
end
