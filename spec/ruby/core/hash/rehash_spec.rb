require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#rehash" do
  it "reorganizes the Hash by recomputing all key hash codes" do
    k1 = Object.new
    k2 = Object.new
    def k1.hash; 0; end
    def k2.hash; 1; end

    h = {}
    h[k1] = :v1
    h[k2] = :v2

    def k1.hash; 1; end

    # The key should no longer be found as the #hash changed.
    # Hash values 0 and 1 should not conflict, even with 1-bit stored hash.
    h.key?(k1).should == false

    h.keys.include?(k1).should == true

    h.rehash.should equal(h)
    h.key?(k1).should == true
    h[k1].should == :v1
  end

  it "calls #hash for each key" do
    k1 = mock('k1')
    k2 = mock('k2')
    v1 = mock('v1')
    v2 = mock('v2')

    v1.should_not_receive(:hash)
    v2.should_not_receive(:hash)

    h = { k1 => v1, k2 => v2 }

    k1.should_receive(:hash).twice.and_return(0)
    k2.should_receive(:hash).twice.and_return(0)

    h.rehash
    h[k1].should == v1
    h[k2].should == v2
  end

  it "removes duplicate keys" do
    a = [1,2]
    b = [1]

    h = {}
    h[a] = true
    h[b] = true
    b << 2
    h.size.should == 2
    h.keys.should == [a, b]
    h.rehash
    h.size.should == 1
    h.keys.should == [a]
  end

  it "removes duplicate keys for large hashes" do
    a = [1,2]
    b = [1]

    h = {}
    h[a] = true
    h[b] = true
    100.times { |n| h[n] = true }
    b << 2
    h.size.should == 102
    h.keys.should.include? a
    h.keys.should.include? b
    h.rehash
    h.size.should == 101
    h.keys.should.include? a
    h.keys.should_not.include? [1]
  end

  it "raises a FrozenError if called on a frozen instance" do
    -> { HashSpecs.frozen_hash.rehash  }.should raise_error(FrozenError)
    -> { HashSpecs.empty_frozen_hash.rehash }.should raise_error(FrozenError)
  end
end
