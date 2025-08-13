require_relative '../../spec_helper'

describe "Hash#safe_dig" do
  it "returns the value for a valid path" do
    h = { foo: { bar: "baz" } }
    h.safe_dig(:foo, :bar).should == "baz"
  end

  it "returns nil when an intermediate value is not a hash or array" do
    h = { foo: "value" }
    h.safe_dig(:foo, :bar).should == nil
  end

  it "returns nil when the index is out of bounds" do
    h = { items: [1, 2, 3] }
    h.safe_dig(:items, 5).should == nil
  end

  it "works with arrays in the path" do
    h = { items: [{ id: 1 }, { id: 2 }] }
    h.safe_dig(:items, 1, :id).should == 2
  end

  it "accepts string and symbol keys" do
    h = { "user" => { "name" => "Dani" } }
    h.safe_dig(:user, :name).should == "Dani"
  end

  it "returns nil when receiver key is nil" do
    h = { user: nil }
    h.safe_dig(:user, :name).should == nil
  end

  it "does not modify the receiver" do
    h = { foo: { bar: "baz" } }
    original = h.dup
    h.safe_dig(:foo, :bar)
    h.should == original
  end
end
