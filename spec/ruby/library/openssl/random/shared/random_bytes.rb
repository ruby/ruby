require_relative '../../../../spec_helper'
require 'openssl'

describe :openssl_random_bytes, shared: true do
  it "generates a random binary string of specified length" do
    (1..64).each do |idx|
      bytes = OpenSSL::Random.send(@method, idx)
      bytes.should be_kind_of(String)
      bytes.length.should == idx
    end
  end

  it "generates different binary strings with subsequent invocations" do
    # quick and dirty check, but good enough
    values = []
    256.times do
      val = OpenSSL::Random.send(@method, 16)
      # make sure the random bytes are not repeating
      values.include?(val).should == false
      values << val
    end
  end

  it "raises ArgumentError on negative arguments" do
    -> {
      OpenSSL::Random.send(@method, -1)
    }.should raise_error(ArgumentError)
  end
end
