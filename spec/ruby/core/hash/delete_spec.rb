require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#delete" do
  it "removes the entry and returns the deleted value" do
    h = { a: 5, b: 2 }
    h.delete(:b).should == 2
    h.should == { a: 5 }
  end

  it "calls supplied block if the key is not found" do
    { a: 1, b: 10, c: 100 }.delete(:d) { 5 }.should == 5
    Hash.new(:default).delete(:d) { 5 }.should == 5
    Hash.new { :default }.delete(:d) { 5 }.should == 5
  end

  it "returns nil if the key is not found when no block is given" do
    { a: 1, b: 10, c: 100 }.delete(:d).should == nil
    Hash.new(:default).delete(:d).should == nil
    Hash.new { :default }.delete(:d).should == nil
  end

  # MRI explicitly implements this behavior
  it "allows removing a key while iterating" do
    h = { a: 1, b: 2 }
    visited = []
    h.each_pair { |k, v|
      visited << k
      h.delete(k)
    }
    visited.should == [:a, :b]
    h.should == {}
  end

  it "allows removing a key while iterating for big hashes" do
    h = { a: 1, b: 2, c: 3, d: 4, e: 5, f: 6, g: 7, h: 8, i: 9, j: 10,
          k: 11, l: 12, m: 13, n: 14, o: 15, p: 16, q: 17, r: 18, s: 19, t: 20,
          u: 21, v: 22, w: 23, x: 24, y: 25, z: 26 }
    visited = []
    h.each_pair { |k, v|
      visited << k
      h.delete(k)
    }
    visited.should == [:a, :b, :c, :d, :e, :f, :g, :h, :i, :j, :k, :l, :m,
                       :n, :o, :p, :q, :r, :s, :t, :u, :v, :w, :x, :y, :z]
    h.should == {}
  end

  it "accepts keys with private #hash method" do
    key = HashSpecs::KeyWithPrivateHash.new
    { key => 5 }.delete(key).should == 5
  end

  it "raises a FrozenError if called on a frozen instance" do
    -> { HashSpecs.frozen_hash.delete("foo") }.should raise_error(FrozenError)
    -> { HashSpecs.empty_frozen_hash.delete("foo") }.should raise_error(FrozenError)
  end
end
