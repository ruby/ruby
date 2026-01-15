require_relative '../../spec_helper'
require 'openssl'

describe "OpenSSL.fixed_length_secure_compare" do
  it "returns true for two strings with the same content" do
    input1 = "the quick brown fox jumps over the lazy dog"
    input2 = "the quick brown fox jumps over the lazy dog"
    OpenSSL.fixed_length_secure_compare(input1, input2).should be_true
  end

  it "returns false for two strings of equal size with different content" do
    input1 = "the quick brown fox jumps over the lazy dog"
    input2 = "the lazy dog jumps over the quick brown fox"
    OpenSSL.fixed_length_secure_compare(input1, input2).should be_false
  end

  it "converts both arguments to strings using #to_str" do
    input1 = mock("input1")
    input1.should_receive(:to_str).and_return("the quick brown fox jumps over the lazy dog")
    input2 = mock("input2")
    input2.should_receive(:to_str).and_return("the quick brown fox jumps over the lazy dog")
    OpenSSL.fixed_length_secure_compare(input1, input2).should be_true
  end

  it "does not accept arguments that are not string and cannot be coerced into strings" do
    -> {
      OpenSSL.fixed_length_secure_compare("input1", :input2)
    }.should raise_error(TypeError, 'no implicit conversion of Symbol into String')

    -> {
      OpenSSL.fixed_length_secure_compare(Object.new, "input2")
    }.should raise_error(TypeError, 'no implicit conversion of Object into String')
  end

  it "raises an ArgumentError for two strings of different size" do
    input1 = "the quick brown fox jumps over the lazy dog"
    input2 = "the quick brown fox"
    -> {
      OpenSSL.fixed_length_secure_compare(input1, input2)
    }.should raise_error(ArgumentError, 'inputs must be of equal length')
  end
end
