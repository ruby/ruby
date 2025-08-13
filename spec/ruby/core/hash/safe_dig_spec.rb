require_relative '../../spec_helper'

describe "Hash#safe_dig" do
  it "behaves like dig when not hitting rock bottom" do
    h = { foo: { bar: "baz" }}
    h.safe_dig(:foo, :bar).should == "baz"
  end

  it "returns nil instead of raising dig error when hitting rock bottom" do
    h = { foo: { bar: '' } }
    h.safe_dig(:foo, :bar, :baz).should == nil
  end
end
