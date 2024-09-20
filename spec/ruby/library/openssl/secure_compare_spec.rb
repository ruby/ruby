require_relative '../../spec_helper'
require 'openssl'

describe "OpenSSL.secure_compare" do
  it "returns true for two strings with the same content" do
    input1 = "the quick brown fox jumps over the lazy dog"
    input2 = "the quick brown fox jumps over the lazy dog"
    OpenSSL.secure_compare(input1, input2).should be_true
  end

  it "returns false for two strings with different content" do
    input1 = "the quick brown fox jumps over the lazy dog"
    input2 = "the lazy dog jumps over the quick brown fox"
    OpenSSL.secure_compare(input1, input2).should be_false
  end

  it "converts both arguments to strings using #to_str, but adds equality check for the original objects" do
    input1 = mock("input1")
    input1.should_receive(:to_str).and_return("the quick brown fox jumps over the lazy dog")
    input2 = mock("input2")
    input2.should_receive(:to_str).and_return("the quick brown fox jumps over the lazy dog")
    OpenSSL.secure_compare(input1, input2).should be_false

    input = mock("input")
    input.should_receive(:to_str).twice.and_return("the quick brown fox jumps over the lazy dog")
    OpenSSL.secure_compare(input, input).should be_true
  end

  it "does not accept arguments that are not string and cannot be coerced into strings" do
    -> {
      OpenSSL.secure_compare("input1", :input2)
    }.should raise_error(TypeError, 'no implicit conversion of Symbol into String')

    -> {
      OpenSSL.secure_compare(Object.new, "input2")
    }.should raise_error(TypeError, 'no implicit conversion of Object into String')
  end
end
