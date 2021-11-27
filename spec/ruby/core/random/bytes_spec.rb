# -*- encoding: binary -*-
require_relative '../../spec_helper'
require_relative 'shared/bytes'

describe "Random#bytes" do
  it_behaves_like :random_bytes, :bytes, Random.new

  it "returns the same output for a given seed" do
    Random.new(33).bytes(2).should == Random.new(33).bytes(2)
  end

  # Should double check this is official spec
  it "returns the same numeric output for a given seed across all implementations and platforms" do
    rnd = Random.new(33)
    rnd.bytes(2).should == "\x14\\"
    rnd.bytes(1000) # skip some
    rnd.bytes(2).should == "\xA1p"
  end

  it "returns the same numeric output for a given huge seed across all implementations and platforms" do
    rnd = Random.new(bignum_value ** 4)
    rnd.bytes(2).should == "_\x91"
    rnd.bytes(1000) # skip some
    rnd.bytes(2).should == "\x17\x12"
  end
end

describe "Random.bytes" do
  it_behaves_like :random_bytes, :bytes, Random
end
