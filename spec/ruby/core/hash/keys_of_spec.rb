require_relative "../../spec_helper"
require_relative "fixtures/classes"

describe "Hash#keys_of" do
  it "returns an array of keys for the given value" do
    h = { a: 9, b: "a", c: 9, d: nil }
    h.keys_of(9).should == [:a, :c]
  end

  it "returns the keys in the order of the hash" do
    h = { c: 9, b: "a", a: 9, d: nil }
    h.keys_of(9).should == [:c, :a]
  end

  it "returns an empty array if the value is not present" do
    h = { c: 9, b: "a", a: 9, d: nil }
    h.keys_of(1).should == []
  end

  it "returns an empty array for an empty hash" do
    h = {}
    h.keys_of(1).should == []
  end
end
