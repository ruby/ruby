require_relative '../../spec_helper'

describe "Hash" do
  it "includes Enumerable" do
    Hash.include?(Enumerable).should == true
  end
end

describe "Hash#hash" do
  it "returns a value which doesn't depend on the hash order" do
    { 0=>2, 11=>1 }.hash.should == { 11=>1, 0=>2 }.hash
  end

  it "returns a value in which element values do not cancel each other out" do
    { a: 2, b: 2 }.hash.should_not == { a: 7, b: 7 }.hash
  end

  it "returns a value in which element keys and values do not cancel each other out" do
    { :a => :a }.hash.should_not == { :b => :b }.hash
  end

  it "generates a hash for recursive hash structures" do
    h = {}
    h[:a] = h
    (h.hash == h[:a].hash).should == true
  end

  it "returns the same hash for recursive hashes" do
    h = {} ; h[:x] = h
    h.hash.should == {x: h}.hash
    h.hash.should == {x: {x: h}}.hash
    # This is because h.eql?(x: h)
    # Remember that if two objects are eql?
    # then the need to have the same hash.
    # Check the Hash#eql? specs!
  end

  it "returns the same hash for recursive hashes through arrays" do
    h = {} ; rec = [h] ; h[:x] = rec
    h.hash.should == {x: rec}.hash
    h.hash.should == {x: [h]}.hash
    # Like above, because h.eql?(x: [h])
  end

  ruby_version_is "3.1" do
    it "allows ommiting values" do
      a = 1
      b = 2

     eval('{a:, b:}.should == { a: 1, b: 2 }')
    end
  end
end
