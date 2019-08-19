require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#shift" do
  it "removes a pair from hash and return it" do
    h = { a: 1, b: 2, "c" => 3, nil => 4, [] => 5 }
    h2 = h.dup

    h.size.times do |i|
      r = h.shift
      r.should be_kind_of(Array)
      h2[r.first].should == r.last
      h.size.should == h2.size - i - 1
    end

    h.should == {}
  end

  # MRI explicitly implements this behavior
  it "allows shifting entries while iterating" do
    h = { a: 1, b: 2, c: 3 }
    visited = []
    shifted = []
    h.each_pair { |k,v|
      visited << k
      shifted << h.shift
    }
    visited.should == [:a, :b, :c]
    shifted.should == [[:a, 1], [:b, 2], [:c, 3]]
    h.should == {}
  end

  it "calls #default with nil if the Hash is empty" do
    h = {}
    def h.default(key)
      key.should == nil
      :foo
    end
    h.shift.should == :foo
  end

  it "returns nil from an empty hash" do
    {}.shift.should == nil
  end

  it "returns (computed) default for empty hashes" do
    Hash.new(5).shift.should == 5
    h = Hash.new { |*args| args }
    h.shift.should == [h, nil]
  end

  it "preserves Hash invariants when removing the last item" do
    h = { :a => 1, :b => 2 }
    h.shift.should == [:a, 1]
    h.shift.should == [:b, 2]
    h[:c] = 3
    h.should == {:c => 3}
  end

  it "raises a #{frozen_error_class} if called on a frozen instance" do
    lambda { HashSpecs.frozen_hash.shift  }.should raise_error(frozen_error_class)
    lambda { HashSpecs.empty_frozen_hash.shift }.should raise_error(frozen_error_class)
  end

  it "works when the hash is at capacity" do
    # We try a wide range of sizes in hopes that this will cover all implementationss base Hash size.
    results = []
    1.upto(100) do |n|
      h = {}
      n.times do |i|
        h[i] = i
      end
      h.shift
      results << h.size
    end

    results.should == 0.upto(99).to_a
  end
end
